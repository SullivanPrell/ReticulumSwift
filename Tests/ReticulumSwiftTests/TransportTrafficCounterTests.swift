import XCTest
@testable import ReticulumSwift

/// Tests for Transport aggregate traffic byte counters.
/// Mirrors Python's `Transport.traffic_rxb` and `Transport.traffic_txb`.
final class TransportTrafficCounterTests: XCTestCase {

    // MARK: - Initial state

    func testInitialTrafficCountersAreZero() {
        let t = Transport()
        XCTAssertEqual(t.trafficRxBytes, 0)
        XCTAssertEqual(t.trafficTxBytes, 0)
    }

    // MARK: - Updated on inbound packets

    func testTrafficRxBytesIncrementedOnInbound() throws {
        let t = Transport()
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "test", aspects: ["traffic"])
        t.ownerIdentity = identity
        t.register(destination: dest)

        final class TestInterface: Interface {
            var name = "rx-test"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = TestInterface()
        t.register(interface: iface)

        // Build a minimal DATA packet via the low-level initialiser used in other tests.
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dest.hash,
            data: Data(repeating: 0xAA, count: 20)
        )
        let raw = try packet.pack()

        let before = t.trafficRxBytes
        iface.inboundHandler?(try Packet.unpack(raw), iface)
        XCTAssertGreaterThan(t.trafficRxBytes, before,
            "trafficRxBytes should increase after inbound packet delivery")
    }

    // MARK: - InterfaceStats includes aggregate traffic

    func testGetInterfaceStatsIncludesAggregateBytes() throws {
        let t = Transport()
        final class TestInterface: Interface {
            var name = "stats-test"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = TestInterface()
        t.register(interface: iface)

        let stats = t.getTransportStats()
        XCTAssertEqual(stats.trafficRxBytes, t.trafficRxBytes)
        XCTAssertEqual(stats.trafficTxBytes, t.trafficTxBytes)
    }

    // MARK: - InterfaceStats includes per-interface frequency

    func testInterfaceStatsIncludesAnnounceFrequency() throws {
        let t = Transport()
        final class TestInterface: Interface {
            var name = "freq-stats"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = TestInterface()
        t.register(interface: iface)

        t.notifyIncomingAnnounce(on: iface)
        t.notifyIncomingAnnounce(on: iface)
        t.notifyIncomingAnnounce(on: iface)

        let ifaceStats = t.getInterfaceStats().first { $0.name == "freq-stats" }
        XCTAssertNotNil(ifaceStats)
        XCTAssertGreaterThan(ifaceStats!.incomingAnnounceFrequency, 0.0,
            "InterfaceStats.incomingAnnounceFrequency should reflect recorded announces")
    }
}

/// Aggregate stats returned by Transport.getTransportStats().
/// Mirrors the top-level stats dict from Python's Reticulum.get_interface_stats().
extension TransportTrafficCounterTests {
    func testTransportStatsAggregatesZeroInitially() {
        let t = Transport()
        let stats = t.getTransportStats()
        XCTAssertEqual(stats.trafficRxBytes, 0)
        XCTAssertEqual(stats.trafficTxBytes, 0)
    }
}
