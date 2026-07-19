import XCTest
@testable import ReticulumSwift

/// Cluster A3: a non-transport shared instance must still carry DATA traffic
/// to and from its directly-connected local clients. Mirrors Python's inbound
/// relay gate `transport_enabled or from_local_client or for_local_client`
/// (RNS/Transport.py:1573).
final class LocalClientDataRelayTests: XCTestCase {

    final class MeshIface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var mode: InterfaceMode = .full
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

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

    private func dataPacket(to dest: Data, headerType: Packet.HeaderType = .type1,
                            transportID: Data? = nil) -> Packet {
        var p = Packet(destinationType: .single, packetType: .data,
                       destinationHash: dest, data: Data(repeating: 0x11, count: 32))
        p.headerType = headerType
        p.transportID = transportID
        return p
    }

    // for_local_client: inbound mesh DATA → deliver to the local client.
    func testMeshDataDeliveredToLocalClientWhenTransportDisabled() throws {
        let t = Transport()
        t.transportEnabled = false
        let serving = ServingIface(name: "Shared Instance[37428]")
        let mesh = MeshIface(name: "mesh")
        t.register(interface: serving)
        t.register(interface: mesh)

        // Local client announces destination D over the serving interface →
        // path hops == 0, next hop = serving interface.
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single, appName: "clientapp")
        serving.inboundHandler?(try Announce.make(for: dest), serving)
        serving.sent.removeAll(); mesh.sent.removeAll()

        // A mesh peer sends DATA addressed to D (HEADER_2, addressed to us as relay).
        mesh.inboundHandler?(dataPacket(to: dest.hash, headerType: .type2, transportID: t.transportInstanceID), mesh)

        let delivered = serving.sent.filter { $0.destinationHash == dest.hash && $0.packetType == .data }
        XCTAssertEqual(delivered.count, 1,
            "mesh DATA for a local client's destination must be delivered to the client")
    }

    // from_local_client: outbound client DATA → forward to the mesh.
    func testLocalClientDataForwardedToMeshWhenTransportDisabled() throws {
        let t = Transport()
        t.transportEnabled = false
        let serving = ServingIface(name: "Shared Instance[37428]")
        let mesh = MeshIface(name: "mesh")
        t.register(interface: serving)
        t.register(interface: mesh)

        // We know a mesh destination E via the mesh interface (hops ≥ 1).
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single, appName: "meshpeer")
        t.injectPath(dest.hash, nextHop: Data(repeating: 0xBB, count: 16),
                     receivedOn: mesh, hops: 2, announcePacketHash: nil)
        serving.sent.removeAll(); mesh.sent.removeAll()

        // The local client sends DATA for E.
        serving.inboundHandler?(dataPacket(to: dest.hash), serving)

        let forwarded = mesh.sent.filter { $0.destinationHash == dest.hash && $0.packetType == .data }
        XCTAssertEqual(forwarded.count, 1,
            "a local client's DATA must be forwarded to the mesh even with transport disabled")
    }

    // Guard: a non-transport node must NOT relay mesh DATA for a non-local destination.
    func testNonTransportNodeDoesNotRelayMeshData() throws {
        let t = Transport()
        t.transportEnabled = false
        let meshA = MeshIface(name: "meshA")
        let meshB = MeshIface(name: "meshB")
        t.register(interface: meshA)
        t.register(interface: meshB)

        // Known mesh destination F via meshA (hops ≥ 1 — NOT a local client).
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single, appName: "peer")
        t.injectPath(dest.hash, nextHop: Data(repeating: 0xCC, count: 16),
                     receivedOn: meshA, hops: 2, announcePacketHash: nil)
        meshA.sent.removeAll(); meshB.sent.removeAll()

        // DATA for F arrives from meshB. We are not transport, not from/for a
        // local client → must NOT relay.
        meshB.inboundHandler?(dataPacket(to: dest.hash, headerType: .type2, transportID: t.transportInstanceID), meshB)

        XCTAssertEqual(meshA.sent.count, 0,
            "a non-transport node must not relay mesh DATA for another destination")
    }
}
