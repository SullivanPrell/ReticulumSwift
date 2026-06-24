import XCTest
@testable import ReticulumSwift

/// Tests for Transport's discovery + blackhole-updater lifecycle methods.
///
/// Mirrors Python's Transport.enable_discovery(), Transport.discover_interfaces(),
/// and Transport.enable_blackhole_updater() — see RNS/Transport.py lines 449–463.
final class TransportDiscoveryIntegrationTests: XCTestCase {

    var transport: Transport!

    override func setUp() {
        super.setUp()
        transport = Transport()
    }

    // MARK: - Initial state

    func testDiscoveryPropertiesInitiallyNil() {
        XCTAssertNil(transport.discoveryHandler,       "discoveryHandler must be nil at init")
        XCTAssertNil(transport.discoveryAnnounceHandler, "discoveryAnnounceHandler must be nil at init")
        XCTAssertNil(transport.blackholeUpdater,       "blackholeUpdater must be nil at init")
    }

    // MARK: - discoverInterfaces

    func testDiscoverInterfacesCreatesDiscoveryHandler() {
        let dir       = tmpDir()
        let validator = AlwaysPassValidator()

        transport.discoverInterfaces(storagePath: dir, stampValidator: validator)

        XCTAssertNotNil(transport.discoveryHandler,
                        "discoveryHandler must be set after discoverInterfaces")
    }

    func testDiscoverInterfacesRegistersAnnounceHandler() {
        let dir       = tmpDir()
        let validator = AlwaysPassValidator()

        transport.discoverInterfaces(storagePath: dir, stampValidator: validator)

        XCTAssertNotNil(transport.discoveryAnnounceHandler,
                        "discoveryAnnounceHandler must be registered after discoverInterfaces")
    }

    func testDiscoverInterfacesIdempotent() {
        let dir       = tmpDir()
        let validator = AlwaysPassValidator()

        transport.discoverInterfaces(storagePath: dir, stampValidator: validator)
        let first = transport.discoveryHandler

        transport.discoverInterfaces(storagePath: dir, stampValidator: validator)

        XCTAssert(transport.discoveryHandler === first,
                  "Second discoverInterfaces call must not replace discoveryHandler")
    }

    func testDiscoverInterfacesWiresCallback() {
        let dir       = tmpDir()
        let validator = AlwaysPassValidator()
        var received  = false

        transport.discoverInterfaces(storagePath: dir, stampValidator: validator) { _ in
            received = true
        }

        // Simulate a discovered interface being fed to the handler.
        let info = makeBackboneInfo()
        transport.discoveryHandler?.interfaceDiscovered(info)

        // discoveryHandler.interfaceDiscovered persists the entry but does NOT invoke the callback —
        // the callback is wired to the InterfaceAnnounceHandler, which calls interfaceDiscovered
        // and then the callback. Here we verify the callback closure was stored on the announce handler.
        XCTAssertNotNil(transport.discoveryAnnounceHandler?.callback,
                        "Announce handler callback must be non-nil after discoverInterfaces with callback")
    }

    // MARK: - stopDiscoverInterfaces

    func testStopDiscoverInterfacesClearsDiscoveryHandler() {
        let dir       = tmpDir()
        let validator = AlwaysPassValidator()

        transport.discoverInterfaces(storagePath: dir, stampValidator: validator)
        transport.stopDiscoverInterfaces()

        XCTAssertNil(transport.discoveryHandler,
                     "discoveryHandler must be nil after stopDiscoverInterfaces")
    }

    func testStopDiscoverInterfacesClearsAnnounceHandler() {
        let dir       = tmpDir()
        let validator = AlwaysPassValidator()

        transport.discoverInterfaces(storagePath: dir, stampValidator: validator)
        transport.stopDiscoverInterfaces()

        XCTAssertNil(transport.discoveryAnnounceHandler,
                     "discoveryAnnounceHandler must be nil after stopDiscoverInterfaces")
    }

    func testStopDiscoverInterfacesIsIdempotent() {
        // Calling stop before start must not crash.
        transport.stopDiscoverInterfaces()
        XCTAssertNil(transport.discoveryHandler)
        XCTAssertNil(transport.discoveryAnnounceHandler)
    }

    // MARK: - enableBlackholeUpdater

    func testEnableBlackholeUpdaterStoresAndStarts() {
        transport.enableBlackholeUpdater()

        XCTAssertNotNil(transport.blackholeUpdater, "blackholeUpdater must be set after enable")
        XCTAssertTrue(transport.blackholeUpdater!.isRunning, "Updater must be running after enable")
    }

    func testEnableBlackholeUpdaterIdempotent() {
        transport.enableBlackholeUpdater()
        let first = transport.blackholeUpdater as AnyObject

        transport.enableBlackholeUpdater()

        XCTAssert(transport.blackholeUpdater as AnyObject === first,
                  "Second enableBlackholeUpdater call must not replace blackholeUpdater")
    }

    func testDisableBlackholeUpdaterClearsProperty() {
        transport.enableBlackholeUpdater()
        transport.disableBlackholeUpdater()

        XCTAssertNil(transport.blackholeUpdater, "blackholeUpdater must be nil after disable")
    }

    func testDisableBlackholeUpdaterStopsIt() {
        transport.enableBlackholeUpdater()
        let updater = transport.blackholeUpdater!
        transport.disableBlackholeUpdater()

        XCTAssertFalse(updater.isRunning, "Updater must be stopped after disable")
    }

    func testDisableBlackholeUpdaterIdempotent() {
        // Calling disable without enable must not crash.
        transport.disableBlackholeUpdater()
        XCTAssertNil(transport.blackholeUpdater)
    }

    // MARK: - listDiscoveredInterfaces delegate

    func testListDiscoveredInterfacesEmptyWhenNoHandler() {
        // No discoveryHandler — must return [] not crash.
        let result = transport.listDiscoveredInterfaces()
        XCTAssertTrue(result.isEmpty,
                      "listDiscoveredInterfaces must return [] when discoveryHandler is nil")
    }

    func testListDiscoveredInterfacesDelegatesWhenHandlerPresent() {
        let dir       = tmpDir()
        let validator = AlwaysPassValidator()
        transport.discoverInterfaces(storagePath: dir, stampValidator: validator)

        let result = transport.listDiscoveredInterfaces()
        // No interfaces stored yet — still [] but no crash.
        XCTAssertTrue(result.isEmpty)
    }

    func testListDiscoveredInterfacesReturnsStoredEntries() {
        let dir       = tmpDir()
        let validator = AlwaysPassValidator()
        transport.discoverInterfaces(storagePath: dir, stampValidator: validator)

        // Seed an interface entry directly through the discoveryHandler.
        let info = makeBackboneInfo()
        transport.discoveryHandler?.interfaceDiscovered(info)

        let result = transport.listDiscoveredInterfaces()
        XCTAssertEqual(result.count, 1, "One interface stored — list must return 1 entry")
        XCTAssertEqual(result.first?.type, "BackboneInterface")
    }
}

// MARK: - Private helpers

private final class AlwaysPassValidator: DiscoveryStampValidator {
    var stampSize: Int { 32 }
    func stampWorkblock(material: Data, expandRounds: Int) -> Data { Data(repeating: 0, count: 32) }
    func stampValue(workblock: Data, stamp: Data) -> Int { 255 }
    func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool { true }
}

private func tmpDir() -> String {
    NSTemporaryDirectory() + "transport-disc-\(UUID().uuidString)"
}

private func makeBackboneInfo() -> DiscoveredInterfaceInfo {
    let tid  = Hashes.randomHash()
    let nid  = Hashes.randomHash()
    let tidHex = RNSUtilities.hexrep(tid, delimit: false)
    let nidHex = RNSUtilities.hexrep(nid, delimit: false)
    let name   = "TEST SERVER"
    let discovery = Hashes.fullHash((tidHex + name).data(using: .utf8)!)
    return DiscoveredInterfaceInfo(
        type: "BackboneInterface", transport: true, name: name,
        received: Date().timeIntervalSince1970,
        stamp: Data(repeating: 0xAB, count: 32), value: 14,
        transportID: tidHex, networkID: nidHex, hops: 2,
        latitude: nil, longitude: nil, height: nil,
        ifacNetname: nil, ifacNetkey: nil,
        reachableOn: "10.0.0.1", port: 4242,
        frequency: nil, bandwidth: nil, sf: nil, cr: nil,
        modulation: nil, channel: nil, configEntry: nil,
        discoveryHash: discovery,
        discovered: Date().timeIntervalSince1970,
        lastHeard: Date().timeIntervalSince1970,
        heardCount: 0
    )
}
