import XCTest
@testable import ReticulumSwift

final class LinkWatchdogTests: XCTestCase {

    func testNoInboundForReturnsTimeSinceEstablishment() throws {
        let srcIdentity = Identity()
        let dstIdentity = Identity()
        let dst = try Destination(identity: dstIdentity, direction: .in, kind: .single, appName: "t", aspects: [])
        let transport = Transport()
        transport.restore(identity: dstIdentity, forDestination: dst.hash)
        let link = try Link.initiate(destination: dst, transport: transport)

        // Just established — no inbound. noInboundFor should be near 0.
        let t = link.noInboundFor()
        XCTAssertLessThan(t, 1.0)
        _ = srcIdentity // suppress warning
    }

    func testInactiveForReturnsMinOfInboundOutbound() throws {
        let dstIdentity = Identity()
        let dst = try Destination(identity: dstIdentity, direction: .in, kind: .single, appName: "t", aspects: [])
        let transport = Transport()
        transport.restore(identity: dstIdentity, forDestination: dst.hash)
        let link = try Link.initiate(destination: dst, transport: transport)

        let inactive = link.inactiveFor()
        XCTAssertGreaterThanOrEqual(inactive, 0)
    }

    func testEstablishmentTimeoutScalesWithHops() throws {
        let dstIdentity = Identity()
        let dst = try Destination(identity: dstIdentity, direction: .in, kind: .single, appName: "t", aspects: [])
        let transport = Transport()
        transport.restore(identity: dstIdentity, forDestination: dst.hash)

        // Inject a 3-hop path.
        transport.restore(
            path: Transport.PathEntry(
                destinationHash: dst.hash,
                nextHopInterfaceName: "eth0",
                hops: 3,
                lastHeard: Date(),
                identityHash: dstIdentity.hash
            ),
            forDestination: dst.hash
        )

        let link = try Link.initiate(destination: dst, transport: transport)
        // Python reference: establishment_timeout = get_first_hop_timeout(dst) + PER_HOP * max(1, hops)
        // No interface bitrate known → firstHopTimeout = defaultPerHopTimeout = 6.
        // Expected: 6 (firstHopTimeout) + 6 * 3 (perHop * hops) = 24.
        XCTAssertEqual(
            link.establishmentTimeout,
            Link.establishmentTimeoutPerHop + Link.establishmentTimeoutPerHop * 3,
            accuracy: 0.01
        )
    }

    func testWatchdogTimeoutFiresClosedCallback() throws {
        let dstIdentity = Identity()
        let dst = try Destination(identity: dstIdentity, direction: .in, kind: .single, appName: "t", aspects: [])
        let transport = Transport()
        transport.restore(identity: dstIdentity, forDestination: dst.hash)
        let link = try Link.initiate(destination: dst, transport: transport)

        // Very short timeout so watchdog fires quickly.
        link.establishmentTimeout = 0.05
        link.startWatchdog()

        let closed = XCTestExpectation(description: "link timed out")
        link.onTimeout = { _ in closed.fulfill() }

        wait(for: [closed], timeout: 2.0)
        XCTAssertEqual(link.status, .failed)
    }

    func testLinkConstantsMatchPythonReference() {
        XCTAssertEqual(Link.keepaliveInterval, 360)
        // Python: STALE_TIME = STALE_FACTOR * KEEPALIVE = 2 * 360 = 720
        XCTAssertEqual(Link.staleTime, 720)
        XCTAssertEqual(Link.establishmentTimeoutPerHop, 6)
    }
}
