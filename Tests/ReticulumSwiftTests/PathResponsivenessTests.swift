import XCTest
@testable import ReticulumSwift

/// Tests that link lifecycle events update path responsiveness state.
/// Python: link timeout → Transport.mark_path_unresponsive(dest_hash)
///         link success → Transport.mark_path_responsive(dest_hash)
final class PathResponsivenessTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    func testSuccessfulLinkEstablishmentMarksPathResponsive() throws {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["resp"])
        bT.ownerIdentity = bId; bT.register(destination: bDest)

        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)

        // Seed path so responsiveness can be tracked
        aT.restore(path: Transport.PathEntry(
            destinationHash: bDest.hash,
            nextHopInterfaceName: aI.name,
            hops: 1,
            lastHeard: Date(),
            identityHash: bId.hash
        ), forDestination: bDest.hash)

        let established = expectation(description: "established")
        aT.onLinkEstablished = { _ in established.fulfill() }
        _ = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [established], timeout: 1.0)

        // Path should be marked responsive after successful establishment
        XCTAssertFalse(aT.pathIsUnresponsive(to: bDest.hash),
            "path should be responsive after successful link establishment")
        _ = (aT, bT)
    }

    func testLinkTimeoutMarksPathUnresponsive() throws {
        let aT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["unresponsive"])

        // Use a black hole interface (doesn't deliver packets)
        final class BlackholeInterface: Interface {
            var name: String = "blackhole"; var bitrate: Int = 0; var isOnline: Bool = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws { /* drop */ }
        }
        let bhole = BlackholeInterface()
        aT.register(interface: bhole)

        aT.restore(path: Transport.PathEntry(
            destinationHash: bDest.hash,
            nextHopInterfaceName: bhole.name,
            hops: 1,
            lastHeard: Date(),
            identityHash: bId.hash
        ), forDestination: bDest.hash)

        let timeout = expectation(description: "timeout")
        let link = try Link.initiate(destination: bDest, transport: aT)
        link.onTimeout = { _ in timeout.fulfill() }
        link.establishmentTimeout = 0.1  // very short timeout
        wait(for: [timeout], timeout: 1.0)

        XCTAssertTrue(aT.pathIsUnresponsive(to: bDest.hash),
            "path should be unresponsive after link establishment timeout")
    }
}
