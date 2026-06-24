import XCTest
@testable import ReticulumSwift

/// Tests for path request handling — verifying that Transport correctly responds
/// to path requests for locally registered destinations.
final class PathRequestResponderTests: XCTestCase {

    final class CapturingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        var mode: InterfaceMode = .full
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    func testPathRequestForLocalDestinationAutoResponds() throws {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "lxmf", aspects: ["delivery"])
        t.ownerIdentity = id
        t.register(destination: dest)

        let iface = CapturingInterface(name: "in")
        t.register(interface: iface)

        // Send path request for dest.hash
        let body = dest.hash + t.transportInstanceID + Data(repeating: 0x01, count: 16)
        let req = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: body
        )
        iface.inboundHandler?(req, iface)

        // Should have sent back an announce as path response
        let announces = iface.sent.filter {
            $0.packetType == .announce && $0.context == .pathResponse
        }
        XCTAssertGreaterThan(announces.count, 0, "should auto-respond to path request")
        if let a = announces.first {
            let decoded = try Announce.validate(a)
            XCTAssertEqual(decoded.destinationHash, dest.hash)
            XCTAssertTrue(decoded.isPathResponse)
        }
    }

    func testPathRequestForCachedDestinationRepliesWithCachedAnnounce() throws {
        let t = Transport()
        t.transportEnabled = true
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "other", aspects: ["service"])

        let iface = CapturingInterface(name: "in")
        t.register(interface: iface)

        // Seed the announce cache manually
        let announcePacket = try Announce.make(for: dest)
        iface.inboundHandler?(announcePacket, iface)  // This caches the announce

        iface.sent.removeAll()

        // Now send a path request
        let body = dest.hash + t.transportInstanceID + Data(repeating: 0x02, count: 16)
        let req = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: body
        )
        iface.inboundHandler?(req, iface)

        // Should have replied with the cached announce (marked as pathResponse)
        let announces = iface.sent.filter {
            $0.packetType == .announce && $0.destinationHash == dest.hash
        }
        XCTAssertGreaterThan(announces.count, 0, "should reply with cached announce")
    }

    func testPathRequestForUnknownDestinationPropagated() throws {
        let t = Transport()
        t.transportEnabled = true

        let iface1 = CapturingInterface(name: "in")
        iface1.mode = .gateway  // DISCOVER_PATHS_FOR: triggers discovery propagation
        let iface2 = CapturingInterface(name: "out")
        t.register(interface: iface1)
        t.register(interface: iface2)

        let unknownHash = Data(repeating: 0xCC, count: 16)
        let body = unknownHash + t.transportInstanceID + Data(repeating: 0x03, count: 16)
        let req = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: body
        )
        iface1.inboundHandler?(req, iface1)

        // Unknown destination: should be forwarded on iface2
        let forwarded = iface2.sent.filter {
            $0.destinationHash == Transport.pathRequestDestinationHash
        }
        XCTAssertGreaterThan(forwarded.count, 0, "unknown path request should be propagated")
    }

    func testPathRequestOnlyAnsweredOncePerTag() throws {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["once"])
        t.ownerIdentity = id
        t.register(destination: dest)

        let iface = CapturingInterface(name: "in")
        t.register(interface: iface)

        let tag = Data(repeating: 0x04, count: 16)
        let body = dest.hash + t.transportInstanceID + tag
        let req = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: body
        )

        // Send the same path request twice (same tag)
        iface.inboundHandler?(req, iface)
        let firstCount = iface.sent.count
        iface.inboundHandler?(req, iface)
        let secondCount = iface.sent.count

        XCTAssertEqual(firstCount, secondCount,
            "duplicate path request (same tag) should not generate another response")
    }
}
