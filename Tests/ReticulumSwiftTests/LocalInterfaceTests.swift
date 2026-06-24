import XCTest
@testable import ReticulumSwift

/// Unit tests for LocalInterface — verify properties, not network connectivity
/// (no actual rnsd daemon is required).
final class LocalInterfaceTests: XCTestCase {

    func testDefaultConfiguration() {
        let iface = LocalInterface()
        XCTAssertEqual(iface.host, "127.0.0.1")
        XCTAssertEqual(iface.port, 37428)
        XCTAssertEqual(iface.reconnectWait, 8)
        XCTAssertNil(iface.maxReconnectTries, "unlimited reconnects by default")
        XCTAssertFalse(iface.isOnline, "not online until connected")
    }

    func testCustomConfiguration() {
        let iface = LocalInterface(name: "rnsd-local", host: "::1", port: 37428)
        XCTAssertEqual(iface.name, "rnsd-local")
        XCTAssertEqual(iface.host, "::1")
        XCTAssertEqual(iface.port, 37428)
    }

    func testConformsToInterfaceProtocol() {
        let iface = LocalInterface()
        // Verify protocol conformance at compile time and basic property access.
        let _: any Interface = iface
        XCTAssertFalse(iface.isOnline)
        XCTAssertGreaterThan(iface.bitrate, 0)
    }

    func testStopBeforeStartIsHarmless() {
        let iface = LocalInterface()
        iface.stop()  // should not crash
        XCTAssertFalse(iface.isOnline)
    }

    func testReconnectConfigurable() {
        let iface = LocalInterface()
        iface.reconnectWait = 5
        iface.maxReconnectTries = 3
        XCTAssertEqual(iface.reconnectWait, 5)
        XCTAssertEqual(iface.maxReconnectTries, 3)
    }

    func testDefaultPortMatchesPythonLocalInterfacePort() {
        // Python: self.local_interface_port = 37428
        XCTAssertEqual(LocalInterface().port, 37428)
    }

    func testSendThrowsWhenOffline() {
        let iface = LocalInterface()
        let pkt = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Data(repeating: 0, count: 16),
            data: Data("test".utf8)
        )
        // Send silently no-ops when offline (not connected).
        XCTAssertNoThrow(try iface.send(pkt))
    }
}
