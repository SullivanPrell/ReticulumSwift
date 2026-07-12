import XCTest
@testable import ReticulumSwift

/// RNS 1.3.6 added two interface features:
///   • `MODE_INTERNAL` (0x07) — added to DISCOVER_PATHS_FOR, with announce
///     suppression when the next-hop interface is roaming/boundary.
///   • `recursive_prs` — forces path discovery on path requests regardless of
///     the interface's mode.
final class RNS136InterfaceFeatureTests: XCTestCase {

    /// Mock interface exposing settable `mode` and `recursivePrs` so the
    /// Transport path-discovery logic can be exercised.
    final class ConfigurableInterface: Interface {
        var name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        var mode: InterfaceMode = .full
        var recursivePrs: Bool = false
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    // MARK: - MODE_INTERNAL

    func testInternalModeIsInDiscoverPathsFor() {
        XCTAssertTrue(InterfaceMode.discoverPathsFor.contains(.internal))
        XCTAssertEqual(InterfaceMode.internal.rawValue, 0x07)
    }

    func testInternalModeSuppressesAnnounceToBoundaryNextHop() {
        // RNS 1.3.7: internal outbound now blocks ONLY a boundary next hop
        // (roaming is no longer blocked — see RNS137AnnouncePropagationTests).
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .internal, nextHopMode: .roaming))
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .internal, nextHopMode: .boundary))
    }

    func testInternalModeForwardsAnnounceToOrdinaryNextHop() {
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .internal, nextHopMode: .full))
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .internal, nextHopMode: .gateway))
    }

    // MARK: - recursive_prs

    func testRecursivePrsDefaultsFalse() {
        let iface = ConfigurableInterface(name: "x")
        XCTAssertFalse(iface.recursivePrs)
    }

    /// A `recursive_prs` interface must trigger discovery of unknown paths even
    /// when its mode (`.full`) is NOT in DISCOVER_PATHS_FOR.
    func testRecursivePrsForcesDiscoveryOnFullModeInterface() throws {
        let t = Transport()
        t.transportEnabled = true

        let ingress = ConfigurableInterface(name: "ingress")
        ingress.mode = .full
        ingress.recursivePrs = true
        let egress = ConfigurableInterface(name: "egress")
        t.register(interface: ingress)
        t.register(interface: egress)

        // Path request for an unknown destination arrives on the recursive_prs iface.
        let unknown = Data(repeating: 0x77, count: 16)
        let body = unknown + t.transportInstanceID + Data(repeating: 0x01, count: 16)
        let req = Packet(destinationType: .plain, packetType: .data,
                         destinationHash: Transport.pathRequestDestinationHash, data: body)
        ingress.inboundHandler?(req, ingress)

        // Discovery should re-broadcast a path request on the *other* interface.
        let forwarded = egress.sent.filter {
            $0.destinationType == .plain && $0.destinationHash == Transport.pathRequestDestinationHash
        }
        XCTAssertGreaterThan(forwarded.count, 0,
            "recursive_prs must forward path requests for unknown destinations even on full-mode interfaces")
    }

    /// Control: a plain `.full` interface *without* recursive_prs must NOT
    /// discover unknown paths (mode not in DISCOVER_PATHS_FOR).
    func testFullModeWithoutRecursivePrsDoesNotDiscover() throws {
        let t = Transport()
        t.transportEnabled = true

        let ingress = ConfigurableInterface(name: "ingress")
        ingress.mode = .full
        ingress.recursivePrs = false
        let egress = ConfigurableInterface(name: "egress")
        t.register(interface: ingress)
        t.register(interface: egress)

        let unknown = Data(repeating: 0x88, count: 16)
        let body = unknown + t.transportInstanceID + Data(repeating: 0x02, count: 16)
        let req = Packet(destinationType: .plain, packetType: .data,
                         destinationHash: Transport.pathRequestDestinationHash, data: body)
        ingress.inboundHandler?(req, ingress)

        let forwarded = egress.sent.filter {
            $0.destinationType == .plain && $0.destinationHash == Transport.pathRequestDestinationHash
        }
        XCTAssertEqual(forwarded.count, 0,
            "full-mode interface without recursive_prs must not discover unknown paths")
    }
}
