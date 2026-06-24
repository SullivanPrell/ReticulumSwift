import XCTest
@testable import ReticulumSwift

/// Tests for `Reticulum.reloadInterface(named:)`.
/// Python parity: `Reticulum.reload_interface(name)` — stop + restart a named interface.
final class ReticulumReloadInterfaceTests: XCTestCase {

    // MARK: - Minimal stub interface

    private final class StubIface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = false
        var inboundHandler: ((Packet, any Interface) -> Void)? = nil
        var rawInboundHandler: ((Data, any Interface) -> Void)? = nil
        var startCallCount = 0
        var stopCallCount = 0

        init(_ name: String) { self.name = name }

        func start() throws {
            startCallCount += 1
            isOnline = true
        }

        func stop() {
            stopCallCount += 1
            isOnline = false
        }

        func send(_ packet: Packet) throws {}
    }

    // MARK: - Test 1: Returns false for a name never registered

    func testReloadInterfaceReturnsFalseForUnknownName() {
        let transport = Transport()
        // Wrap Transport in a minimal Reticulum-like context.
        // We test via Transport directly since Reticulum.reloadInterface delegates to transport.
        // Instead, test directly on a Reticulum instance without a registered interface.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-reload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let config = Reticulum.Configuration(storagePath: tmpDir)
        let rns = Reticulum(configuration: config)

        let result = rns.reloadInterface(named: "nonexistent-interface")
        XCTAssertFalse(result, "reloadInterface should return false when the name is not registered")
    }

    // MARK: - Test 2: Returns true after registering an interface with that name

    func testReloadInterfaceReturnsTrueWhenInterfaceRegistered() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-reload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let config = Reticulum.Configuration(storagePath: tmpDir)
        let rns = Reticulum(configuration: config)

        let iface = StubIface("my-interface")
        rns.transport.register(interface: iface)

        let result = rns.reloadInterface(named: "my-interface")
        XCTAssertTrue(result, "reloadInterface should return true when the named interface exists")
    }

    // MARK: - Test 3: After reload, getInterfaceStats still includes an entry for that name

    func testReloadInterfaceStatsStillContainsName() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-reload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let config = Reticulum.Configuration(storagePath: tmpDir)
        let rns = Reticulum(configuration: config)

        let iface = StubIface("persistent-interface")
        rns.transport.register(interface: iface)

        rns.reloadInterface(named: "persistent-interface")

        let stats = rns.getInterfaceStats()
        let names = stats.map { $0.name }
        XCTAssertTrue(names.contains("persistent-interface"),
            "getInterfaceStats should still include the interface after reload")
    }

    // MARK: - Test 4: Reload on an already-halted interface does not crash, returns true

    func testReloadInterfaceOnHaltedInterfaceDoesNotCrash() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-reload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let config = Reticulum.Configuration(storagePath: tmpDir)
        let rns = Reticulum(configuration: config)

        let iface = StubIface("halted-interface")
        rns.transport.register(interface: iface)

        // First halt the interface
        rns.transport.halt(interfaceName: "halted-interface")
        XCTAssertFalse(iface.isOnline, "interface should be offline after halt")

        // Now reload — should not crash and should return true
        let result = rns.reloadInterface(named: "halted-interface")
        XCTAssertTrue(result, "reloadInterface on a halted interface should return true (not crash)")
    }

    // MARK: - Test 5: Reload calls stop then start on the interface

    func testReloadInterfaceCallsStopThenStart() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-reload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let config = Reticulum.Configuration(storagePath: tmpDir)
        let rns = Reticulum(configuration: config)

        let iface = StubIface("cycle-interface")
        rns.transport.register(interface: iface)

        rns.reloadInterface(named: "cycle-interface")

        XCTAssertEqual(iface.stopCallCount, 1, "reloadInterface should call stop once")
        XCTAssertEqual(iface.startCallCount, 1, "reloadInterface should call start once")
    }
}
