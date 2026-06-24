import XCTest
@testable import ReticulumSwift

/// Tests for per-interface current RX/TX speed tracking.
///
/// Mirrors Python's `count_traffic_loop` which computes per-interface
/// `current_rx_speed` and `current_tx_speed` (bits/sec) from byte-count
/// deltas, and updates `Transport.speed_rx` / `speed_tx` aggregates.
final class InterfaceSpeedTrackingTests: XCTestCase {

    // MARK: - Initial state

    func testCurrentSpeedInitiallyZero() {
        let t = Transport()
        final class TestIface: Interface {
            var name = "s0"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = TestIface()
        t.register(interface: iface)
        XCTAssertEqual(t.currentRxSpeed(for: iface), 0.0)
        XCTAssertEqual(t.currentTxSpeed(for: iface), 0.0)
    }

    // MARK: - Speed computed from byte deltas

    func testSpeedComputedFromByteDelta() {
        let t = Transport()
        final class CountingIface: Interface {
            var name = "counter"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            var rxBytes: Int = 0
            var txBytes: Int = 0
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = CountingIface()
        t.register(interface: iface)

        // Seed baseline at t=0
        t.sampleInterfaceSpeeds(now: 0)

        // Simulate 1000 bytes received over 1 second.
        iface.rxBytes = 1000
        iface.txBytes = 500
        t.sampleInterfaceSpeeds(now: 1.0)

        // RX: 1000 bytes in 1s = 8000 bits/s
        XCTAssertEqual(t.currentRxSpeed(for: iface), 8000.0, accuracy: 1.0,
            "RX speed should be 8000 bits/s (1000 bytes × 8 / 1s)")
        // TX: 500 bytes in 1s = 4000 bits/s
        XCTAssertEqual(t.currentTxSpeed(for: iface), 4000.0, accuracy: 1.0,
            "TX speed should be 4000 bits/s (500 bytes × 8 / 1s)")
    }

    // MARK: - Aggregate Transport speed

    func testAggregateSpeedSumsInterfaces() {
        let t = Transport()
        final class CountingIface: Interface {
            var name: String; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            var rxBytes: Int = 0; var txBytes: Int = 0
            init(_ n: String) { name = n }
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let a = CountingIface("a"); let b = CountingIface("b")
        t.register(interface: a); t.register(interface: b)

        t.sampleInterfaceSpeeds(now: 0)
        a.rxBytes = 500; b.rxBytes = 500
        t.sampleInterfaceSpeeds(now: 1.0)

        // Both interfaces together = 1000 bytes in 1s = 8000 bits/s aggregate
        XCTAssertEqual(t.speedRx, 8000.0, accuracy: 1.0,
            "aggregate speedRx should sum both interfaces")
    }

    // MARK: - Exposed in InterfaceStats

    func testInterfaceStatsIncludesCurrentSpeed() {
        let t = Transport()
        final class CountingIface: Interface {
            var name = "stats-speed"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            var rxBytes: Int = 0; var txBytes: Int = 0
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = CountingIface()
        t.register(interface: iface)
        t.sampleInterfaceSpeeds(now: 0)
        iface.rxBytes = 800
        t.sampleInterfaceSpeeds(now: 1.0)

        let stats = t.getInterfaceStats().first { $0.name == "stats-speed" }
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats!.currentRxSpeed, 6400.0, accuracy: 1.0,
            "InterfaceStats.currentRxSpeed should reflect last sampled value")
    }

    // MARK: - TransportStats includes aggregate speeds

    func testTransportStatsIncludesAggregateSpeed() {
        let t = Transport()
        final class CountingIface: Interface {
            var name = "ts-speed"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            var rxBytes: Int = 0; var txBytes: Int = 0
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = CountingIface()
        t.register(interface: iface)
        t.sampleInterfaceSpeeds(now: 0)
        iface.rxBytes = 1000; iface.txBytes = 200
        t.sampleInterfaceSpeeds(now: 1.0)

        let stats = t.getTransportStats()
        XCTAssertEqual(stats.speedRx, 8000.0, accuracy: 1.0)
        XCTAssertEqual(stats.speedTx, 1600.0, accuracy: 1.0)
    }

    // MARK: - Zero delta produces zero speed

    func testZeroDeltaProducesZeroSpeed() {
        let t = Transport()
        final class TestIface: Interface {
            var name = "zero"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            var rxBytes: Int = 100; var txBytes: Int = 50
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = TestIface()
        t.register(interface: iface)
        t.sampleInterfaceSpeeds(now: 0)
        // No change in byte counts.
        t.sampleInterfaceSpeeds(now: 1.0)
        XCTAssertEqual(t.currentRxSpeed(for: iface), 0.0)
        XCTAssertEqual(t.currentTxSpeed(for: iface), 0.0)
    }
}
