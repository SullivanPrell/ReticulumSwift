import XCTest
@testable import ReticulumSwift

/// Tests for Transport management API methods mirroring Python's Transport.
///   - `Transport.prioritize_interfaces()` — sort by bitrate descending
///   - `Transport.drop_announce_queues()` — clear all announce queues
final class TransportManagementAPITests: XCTestCase {

    final class MockInterface: Interface {
        var name: String
        var bitrate: Int
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?

        init(name: String, bitrate: Int) { self.name = name; self.bitrate = bitrate }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}
    }

    // MARK: - prioritize_interfaces

    func testPrioritizeInterfacesSortsByBitrateDescending() {
        let t = Transport()
        let slow = MockInterface(name: "slow", bitrate: 1200)
        let fast = MockInterface(name: "fast", bitrate: 1_000_000)
        let medium = MockInterface(name: "medium", bitrate: 50_000)

        t.register(interface: slow)
        t.register(interface: fast)
        t.register(interface: medium)

        t.prioritizeInterfaces()

        let names = t.interfaces.map { $0.name }
        XCTAssertEqual(names[0], "fast", "fastest interface should be first")
        XCTAssertEqual(names[1], "medium")
        XCTAssertEqual(names[2], "slow")
    }

    func testPrioritizeInterfacesNoOpWithSingleInterface() {
        let t = Transport()
        let iface = MockInterface(name: "only", bitrate: 9600)
        t.register(interface: iface)
        t.prioritizeInterfaces()
        XCTAssertEqual(t.interfaces.count, 1)
        XCTAssertEqual(t.interfaces.first?.name, "only")
    }

    // MARK: - drop_announce_queues

    func testDropAnnounceQueues() {
        let t = Transport()
        t.dropAnnounceQueues()
        // Should not crash and queues should be empty
        // (hard to verify internal state, but at minimum it should not throw)
    }

    // MARK: - Transport.interfaces public access

    func testInterfacesPubliclyReadable() {
        let t = Transport()
        let iface = MockInterface(name: "a", bitrate: 0)
        t.register(interface: iface)
        XCTAssertEqual(t.interfaces.count, 1)
    }
}
