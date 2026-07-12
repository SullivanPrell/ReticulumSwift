import XCTest
@testable import ReticulumSwift

/// RNS 1.3.7 reworked the announce-propagation filter in `Transport.outbound()`:
///   • A relayed announce is blocked when the next hop toward its source does
///     not exist (unless the destination is instance-local).
///   • `announces_from_internal == false` blocks relaying announces whose next
///     hop is an `internal`-mode interface.
///   • `internal`-mode outbound interfaces now only block on a `boundary`
///     next hop (previously they also blocked `roaming`).
///   • Instance-local destinations bypass the roaming/boundary/internal blocks.
final class RNS137AnnouncePropagationTests: XCTestCase {

    // MARK: - internal-mode behavior change (roaming now allowed)

    func testInternalOutboundNowForwardsToRoamingNextHop() {
        // Behavior change vs 1.3.6: internal outbound no longer blocks a
        // roaming next hop.
        XCTAssertTrue(Transport.shouldForwardAnnounce(
            outboundMode: .internal, nextHopMode: .roaming))
    }

    func testInternalOutboundStillBlocksBoundaryNextHop() {
        XCTAssertFalse(Transport.shouldForwardAnnounce(
            outboundMode: .internal, nextHopMode: .boundary))
    }

    func testInternalOutboundForwardsToOrdinaryNextHop() {
        XCTAssertTrue(Transport.shouldForwardAnnounce(
            outboundMode: .internal, nextHopMode: .full))
        XCTAssertTrue(Transport.shouldForwardAnnounce(
            outboundMode: .internal, nextHopMode: .gateway))
    }

    // MARK: - missing next hop

    func testBlockWhenNextHopMissingAndNotLocal() {
        // No next-hop interface toward the source and the destination is not
        // instance-local → block on every outbound mode.
        for mode in [InterfaceMode.full, .gateway, .roaming, .boundary, .internal] {
            XCTAssertFalse(Transport.shouldForwardAnnounce(
                outboundMode: mode, nextHopMode: nil, localDestination: false),
                "mode \(mode) should block a relayed announce with no next hop")
        }
    }

    func testLocalDestinationForwardsEvenWithNoNextHop() {
        // A node's own destination announce has no next-hop interface but must
        // still be broadcast.
        for mode in [InterfaceMode.full, .gateway, .roaming, .boundary, .internal] {
            XCTAssertTrue(Transport.shouldForwardAnnounce(
                outboundMode: mode, nextHopMode: nil, localDestination: true),
                "mode \(mode) should forward an instance-local announce")
        }
    }

    // MARK: - announces_from_internal

    func testAnnouncesFromInternalFalseBlocksInternalNextHop() {
        XCTAssertFalse(Transport.shouldForwardAnnounce(
            outboundMode: .full, nextHopMode: .internal,
            localDestination: false, announcesFromInternal: false))
    }

    func testAnnouncesFromInternalTrueAllowsInternalNextHop() {
        XCTAssertTrue(Transport.shouldForwardAnnounce(
            outboundMode: .full, nextHopMode: .internal,
            localDestination: false, announcesFromInternal: true))
    }

    func testLocalDestinationBypassesAnnouncesFromInternalBlock() {
        // announces_from_internal only gates relayed (non-local) announces.
        XCTAssertTrue(Transport.shouldForwardAnnounce(
            outboundMode: .full, nextHopMode: .internal,
            localDestination: true, announcesFromInternal: false))
    }

    // MARK: - roaming / boundary unchanged

    func testRoamingAndBoundaryUnchanged() {
        // roaming blocks roaming/boundary next hops
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .roaming, nextHopMode: .roaming))
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .roaming, nextHopMode: .boundary))
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .roaming, nextHopMode: .full))
        // boundary blocks only roaming next hops
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .boundary, nextHopMode: .roaming))
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .boundary, nextHopMode: .boundary))
        // AP always blocks
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .accessPoint, nextHopMode: .full))
    }

    // MARK: - property default

    func testAnnouncesFromInternalDefaultsTrue() {
        let iface = TCPClientInterface(name: "x", host: "127.0.0.1", port: 4242)
        XCTAssertTrue(iface.announcesFromInternal)
    }
}
