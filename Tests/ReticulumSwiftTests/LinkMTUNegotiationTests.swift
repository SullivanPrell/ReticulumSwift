import XCTest
@testable import ReticulumSwift

/// Verifies that an established Link adopts the negotiated MTU end-to-end
/// (Python `Link.mtu` / `mtu_from_lr_packet` / `mtu_from_lp_packet`):
///   • initiator signals the next-hop interface HW MTU,
///   • responder adopts it and confirms it in the proof,
///   • initiator adopts the confirmed value,
///   • both sides derive `mdu` from the negotiated MTU.
final class LinkMTUNegotiationTests: XCTestCase {

    /// Loopback interface with a configurable hardware MTU.
    final class MTULoopback: Interface {
        let name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        weak var paired: MTULoopback?
        let hwMtu: Int?
        let fixedMtu: Bool

        init(name: String, hwMtu: Int?, fixedMtu: Bool) {
            self.name = name; self.hwMtu = hwMtu; self.fixedMtu = fixedMtu
        }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    private func establish(hwMtu: Int?) throws -> (initiator: Link, responder: Link) {
        let aTransport = Transport()
        let bTransport = Transport()

        let bIdentity = Identity()
        let bDest = try Destination(identity: bIdentity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["mtu"])
        bTransport.ownerIdentity = bIdentity
        bTransport.register(destination: bDest)

        let aIface = MTULoopback(name: "A", hwMtu: hwMtu, fixedMtu: hwMtu != nil)
        let bIface = MTULoopback(name: "B", hwMtu: hwMtu, fixedMtu: hwMtu != nil)
        aIface.paired = bIface; bIface.paired = aIface
        aTransport.register(interface: aIface)
        bTransport.register(interface: bIface)

        // Seed A's path so nextHopInterfaceHwMtu(for:) resolves the loopback iface.
        aTransport.restore(
            path: Transport.PathEntry(destinationHash: bDest.hash, nextHopInterfaceName: aIface.name,
                                      hops: 0, lastHeard: Date(), identityHash: bIdentity.hash),
            forDestination: bDest.hash)

        let aEst = expectation(description: "a established")
        aTransport.onLinkEstablished = { _ in aEst.fulfill() }

        let aLink = try Link.initiate(destination: bDest, transport: aTransport)
        wait(for: [aEst], timeout: 2.0)
        let bLink = try XCTUnwrap(bTransport.links[aLink.linkID!])
        return (aLink, bLink)
    }

    func testDefaultMTUWhenInterfaceHasNoHWMTU() throws {
        // hwMtu nil → no signalling beyond the default → both sides at 500.
        let (a, b) = try establish(hwMtu: nil)
        XCTAssertEqual(a.getMtu(), Constants.mtu)
        XCTAssertEqual(b.getMtu(), Constants.mtu)
        XCTAssertEqual(a.getMdu(), Constants.linkMdu)
    }

    func testHigherMTUIsNegotiatedAndAdoptedOnBothSides() throws {
        let highMtu = 1500
        let (a, b) = try establish(hwMtu: highMtu)
        XCTAssertEqual(a.getMtu(), highMtu, "initiator must adopt the confirmed MTU")
        XCTAssertEqual(b.getMtu(), highMtu, "responder must adopt the requested MTU")
        // mdu must scale with the negotiated MTU and agree on both sides.
        XCTAssertEqual(a.getMdu(), b.getMdu())
        XCTAssertGreaterThan(a.getMdu() ?? 0, Constants.linkMdu)
    }

    func testSignallingRoundTrip() throws {
        for mtu in [500, 1064, 1500, 262_144] {
            let bytes = Link.mtuSignallingBytes(mtu: mtu)
            XCTAssertEqual(Link.mtuFromSignalling(bytes), mtu, "round-trip MTU \(mtu)")
        }
    }
}
