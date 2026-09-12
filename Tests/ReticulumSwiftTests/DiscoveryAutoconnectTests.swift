//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest
@testable import ReticulumSwift

/// Dialling and monitoring discovered endpoints—Python's `Discovery.InterfaceDiscovery`
/// autoconnect half (`Discovery.py:602-781`).
///
/// The receive side has persisted discovered endpoints since RNS 1.4.0 and nothing ever dialled
/// them, so `rnstatus -D` listed peers an operator then had to add to their config by hand.
final class DiscoveryAutoconnectTests: XCTestCase {

    /// An interface whose online state the test drives. `BackboneInterface.isOnline` is
    /// `private(set)`, set by its own connection machinery, so the monitor tests stand a double
    /// in for a dialled peer rather than pretending to connect one.
    final class MonitoredInterface: Interface {
        var name: String
        var bitrate: Int = 5_000_000
        var isOnline: Bool
        var inboundHandler: ((Packet, any Interface) -> Void)?
        let interfaceState = InterfaceState()
        init(name: String, online: Bool = false) { self.name = name; self.isOnline = online }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}
    }

    /// A dialled peer as the monitor sees one: attached, marked, and offline.
    private func monitored(name: String = "peer", online: Bool = false) -> MonitoredInterface {
        let iface = MonitoredInterface(name: name, online: online)
        iface.autoconnectHash = Data(repeating: 0xEE, count: 32)
        transport.register(interface: iface)
        discovery.monitorInterface(iface)
        return iface
    }

    private var transport: Transport!
    private var discovery: InterfaceDiscovery!
    private var storage: URL!

    override func setUp() {
        super.setUp()
        storage = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("autoconnect-\(UUID().uuidString)")
        transport = Transport()
        transport.transportIdentity = Identity()
        discovery = InterfaceDiscovery(storagePath: storage.path)
        discovery.transport = transport
        Reticulum.storedMaxAutoconnectedInterfaces = 4
    }

    override func tearDown() {
        // The monitor job is a live background loop once a test starts one, and it logs on every
        // pass. Left running it outlives the test and interleaves its output with the next
        // suite's.
        discovery.stopMonitoring()
        Reticulum.storedMaxAutoconnectedInterfaces = 0
        Reticulum.storedAutoconnectInterfaceMode = nil
        Reticulum.storedAutoconnectInterfaceGravity = nil
        Reticulum.storedAutoconnectAnnouncesToInternal = nil
        try? FileManager.default.removeItem(at: storage)
        super.tearDown()
    }

    /// A discovered endpoint, shaped the way `InterfaceAnnounceHandler` leaves one.
    private func discovered(type: String = "BackboneInterface",
                            reachableOn: String? = "hub.example.net",
                            port: Int? = 4965,
                            name: String = "Example hub") -> DiscoveredInterfaceInfo {
        let now = Date().timeIntervalSince1970
        return DiscoveredInterfaceInfo(
            type: type, transport: true, name: name, received: now,
            stamp: Data(repeating: 0xAB, count: 32), value: 16,
            transportID: String(repeating: "a", count: 32),
            networkID: String(repeating: "b", count: 32), hops: 1,
            latitude: nil, longitude: nil, height: nil,
            ifacNetname: nil, ifacNetkey: nil,
            reachableOn: reachableOn, port: port,
            frequency: nil, bandwidth: nil, sf: nil, cr: nil,
            modulation: nil, channel: nil, configEntry: nil,
            discoveryHash: Data(repeating: 0xCD, count: 32),
            discovered: now, lastHeard: now, heardCount: 1)
    }

    // MARK: - The address filters

    /// Python: `is_ygg_ipv6` (`Discovery.py:877-879`)—`200::/7`, which is the Yggdrasil range.
    ///
    /// Anything in it is only reachable through a running Yggdrasil node, and nothing here can
    /// tell whether one is running.
    func testYggdrasilAddressesAreRecognised() {
        XCTAssertTrue(InterfaceDiscoveryHelpers.isYggIPv6("200::1"))
        XCTAssertTrue(InterfaceDiscoveryHelpers.isYggIPv6("201:1234::5"))
        XCTAssertTrue(InterfaceDiscoveryHelpers.isYggIPv6("21f:ffff:ffff:ffff:ffff:ffff:ffff:ffff"))
        XCTAssertFalse(InterfaceDiscoveryHelpers.isYggIPv6("2001:db8::1"),
                       "the boundary matters: 2001:… is ordinary global unicast")
        XCTAssertFalse(InterfaceDiscoveryHelpers.isYggIPv6("1ff::1"))
        XCTAssertFalse(InterfaceDiscoveryHelpers.isYggIPv6("192.168.1.1"))
        XCTAssertFalse(InterfaceDiscoveryHelpers.isYggIPv6("not an address"))
    }

    /// Python: `is_onion_address` (`Discovery.py:881-883`)—suffix match, case-insensitive.
    func testOnionAddressesAreRecognised() {
        XCTAssertTrue(InterfaceDiscoveryHelpers.isOnionAddress("expyuzz4wqqyqhjn.onion"))
        XCTAssertTrue(InterfaceDiscoveryHelpers.isOnionAddress("EXAMPLE.ONION"))
        XCTAssertFalse(InterfaceDiscoveryHelpers.isOnionAddress("onion.example.net"))
        XCTAssertFalse(InterfaceDiscoveryHelpers.isOnionAddress(""))
    }

    /// Python: `is_invalid_ip_address` (`Discovery.py:885-888`)—a two-entry deny list, not a
    /// range check. `127.0.0.2` is a loopback address and is *not* on it.
    func testTheInvalidAddressListIsExactlyTwoEntries() {
        XCTAssertTrue(InterfaceDiscoveryHelpers.isInvalidIPAddress("127.0.0.1"))
        XCTAssertTrue(InterfaceDiscoveryHelpers.isInvalidIPAddress("0.0.0.0"))
        XCTAssertFalse(InterfaceDiscoveryHelpers.isInvalidIPAddress("127.0.0.2"))
        XCTAssertFalse(InterfaceDiscoveryHelpers.isInvalidIPAddress("10.0.0.1"))
    }

    // MARK: - The autoconnect gates

    func testAutoconnectDialsADiscoveredBackbone() {
        discovery.autoconnect(discovered())

        let dialled = transport.interfaces.compactMap { $0 as? BackboneInterface }
        XCTAssertEqual(dialled.count, 1)
        XCTAssertEqual(dialled.first?.host, "hub.example.net")
        XCTAssertEqual(dialled.first?.port, 4965)
        XCTAssertEqual(dialled.first?.name, "Example hub")
    }

    /// A discovered `TCPServerInterface` is dialled as a Backbone client, because that's the
    /// client type for a listening endpoint (`Discovery.py:730-758`).
    ///
    /// Python degrades to
    /// `TCPClientInterface` only on platforms with no Backbone, and then declines to connect.
    func testADiscoveredListenerIsDialledAsABackboneClient() {
        discovery.autoconnect(discovered(type: "TCPServerInterface"))
        XCTAssertEqual(transport.interfaces.compactMap { $0 as? BackboneInterface }.count, 1)
    }

    /// The dialled interface carries the endpoint hash and the announcing network's identity, so
    /// the monitor job can tell an auto-connected interface from a configured one
    /// (`Discovery.py:765-766`).
    func testTheDialledInterfaceIsMarkedAsAutoconnected() throws {
        let info = discovered()
        discovery.autoconnect(info)

        let iface = try XCTUnwrap(transport.interfaces.first)
        XCTAssertEqual(iface.autoconnectHash, discovery.endpointHash(info))
        XCTAssertEqual(iface.autoconnectSource, info.networkID)
        XCTAssertEqual(discovery.autoconnectCount(), 1)
    }

    /// Off by default: `autoconnect_discovered_interfaces` defaults to 0, and 0 disables the
    /// whole subsystem (`Reticulum.should_autoconnect_discovered_interfaces`).
    func testAutoconnectIsOffWhenTheLimitIsZero() {
        Reticulum.storedMaxAutoconnectedInterfaces = 0
        discovery.autoconnect(discovered())
        XCTAssertTrue(transport.interfaces.isEmpty)
    }

    func testTheLimitIsRespected() {
        Reticulum.storedMaxAutoconnectedInterfaces = 2
        for i in 0..<4 {
            var info = discovered(reachableOn: "hub\(i).example.net", name: "hub\(i)")
            info.discoveryHash = Data(repeating: UInt8(i), count: 32)
            discovery.autoconnect(info)
        }
        XCTAssertEqual(transport.interfaces.count, 2)
    }

    /// Only two types are dialled (`AUTOCONNECT_TYPES`).
    ///
    /// An RNode is discoverable but not
    /// dialable—there's no radio at the other end of a hostname.
    func testUndialableTypesAreSkipped() {
        for type in ["RNodeInterface", "I2PInterface", "TCPClientInterface", "KISSInterface"] {
            discovery.autoconnect(discovered(type: type))
        }
        XCTAssertTrue(transport.interfaces.isEmpty)
    }

    /// Each filter alone stops the dial.
    ///
    /// Yggdrasil and Tor addresses need a daemon this node
    /// can't detect; the two deny-listed IPs are this node talking to itself
    /// (`Discovery.py:738-747`).
    func testTheAddressFiltersStopTheDial() {
        discovery.autoconnect(discovered(reachableOn: "200::1"))
        discovery.autoconnect(discovered(reachableOn: "expyuzz4wqqyqhjn.onion"))
        discovery.autoconnect(discovered(reachableOn: "127.0.0.1"))
        discovery.autoconnect(discovered(reachableOn: "0.0.0.0"))
        XCTAssertTrue(transport.interfaces.isEmpty)

        // An ordinary loopback address that isn't on the deny list still dials, which is what
        // makes the assertion above about the list rather than about loopback.
        discovery.autoconnect(discovered(reachableOn: "127.0.0.2"))
        XCTAssertEqual(transport.interfaces.count, 1)
    }

    func testAnEndpointWithNoAddressIsSkipped() {
        discovery.autoconnect(discovered(reachableOn: nil))
        XCTAssertTrue(transport.interfaces.isEmpty)
    }

    // MARK: - Duplicate suppression

    func testTheSameEndpointIsNotDialledTwice() {
        let info = discovered()
        discovery.autoconnect(info)
        discovery.autoconnect(info)
        XCTAssertEqual(transport.interfaces.count, 1)
    }

    /// An endpoint the operator already configured by hand is matched on host and port, not on
    /// the autoconnect hash—which a configured interface doesn't carry (`Discovery.py:700-712`).
    func testAConfiguredInterfaceToTheSameEndpointSuppressesTheDial() {
        transport.register(interface: BackboneInterface(name: "manual",
                                                        host: "hub.example.net", port: 4965))
        discovery.autoconnect(discovered())
        XCTAssertEqual(transport.interfaces.count, 1, "the manually configured one, unchanged")
    }

    /// Same host, different port is a different endpoint.
    func testADifferentPortIsADifferentEndpoint() {
        transport.register(interface: BackboneInterface(name: "manual",
                                                        host: "hub.example.net", port: 4242))
        discovery.autoconnect(discovered())
        XCTAssertEqual(transport.interfaces.count, 2)
    }

    // MARK: - Applied policy

    /// A transport node adopts the discovered peer as a gateway; a non-transport node leaves the
    /// mode unset (`Discovery.py:767-769`). `AC_GRAVITY` is 0, so an auto-connected peer never
    /// outranks a configured one in path selection.
    func testATransportNodeAdoptsTheEndpointAsAGateway() throws {
        transport.transportEnabled = true

        discovery.autoconnect(discovered())
        let iface = try XCTUnwrap(transport.interfaces.first)
        XCTAssertEqual(iface.mode, .gateway)
        XCTAssertEqual(iface.gravity, 0)
    }

    func testTheConfiguredPolicyOverridesTheDefaults() throws {
        Reticulum.storedAutoconnectInterfaceMode = .accessPoint
        Reticulum.storedAutoconnectInterfaceGravity = 7
        Reticulum.storedAutoconnectAnnouncesToInternal = true

        discovery.autoconnect(discovered())
        let iface = try XCTUnwrap(transport.interfaces.first)
        XCTAssertEqual(iface.mode, .accessPoint)
        XCTAssertEqual(iface.gravity, 7)
        XCTAssertEqual(iface.announcesToInternal, true)
    }

    /// A discovered endpoint that published its segment credentials is joined on that segment,
    /// which is the whole point of `publish_ifac` (`Discovery.py:753-754`).
    func testPublishedIfacCredentialsAreAdopted() throws {
        var info = discovered()
        info.ifacNetname = "segment"
        info.ifacNetkey = "passphrase"

        discovery.autoconnect(info)
        let iface = try XCTUnwrap(transport.interfaces.first)
        XCTAssertEqual(iface.ifacNetname, "segment")
        XCTAssertEqual(iface.ifacNetkey, "passphrase")
        XCTAssertNotNil(iface.ifacKey, "the segment key has to be derived, not just recorded")
    }

    // MARK: - Monitoring

    /// A monitored interface that goes offline is stamped, and stamped once—the timestamp is
    /// how long it's been down, so re-stamping every pass would keep it alive forever
    /// (`Discovery.py:625-630`).
    func testAnOfflineInterfaceIsStampedOnce() throws {
        let iface = monitored()

        discovery.monitorTick()
        let firstStamp = try XCTUnwrap(iface.autoconnectDown)

        discovery.monitorTick()
        XCTAssertEqual(iface.autoconnectDown, firstStamp)
    }

    /// Coming back up clears the stamp, so a peer that flaps never accumulates toward the
    /// detach threshold (`Discovery.py:620-623`).
    func testReconnectingClearsTheDownStamp() throws {
        let iface = monitored()

        discovery.monitorTick()
        XCTAssertNotNil(iface.autoconnectDown)

        iface.isOnline = true
        discovery.monitorTick()
        XCTAssertNil(iface.autoconnectDown)
    }

    /// Down for longer than the threshold and the interface is detached, so a node that has
    /// moved doesn't hold a dead slot forever (`Discovery.py:631-635`).
    func testAnInterfaceDownPastTheThresholdIsDetached() throws {
        let iface = monitored()

        iface.autoconnectDown = Date().timeIntervalSince1970 - InterfaceDiscovery.detachThreshold - 1
        discovery.monitorTick()

        XCTAssertTrue(transport.interfaces.isEmpty)
        XCTAssertEqual(discovery.autoconnectCount(), 0)
    }

    /// A configured interface is never detached by the monitor, however long it's been down—it
    /// isn't in `monitored_interfaces` at all.
    func testAConfiguredInterfaceIsNeverDetached() {
        let manual = MonitoredInterface(name: "manual")
        transport.register(interface: manual)

        manual.autoconnectDown = Date().timeIntervalSince1970 - 10_000
        discovery.monitorTick()

        XCTAssertEqual(transport.interfaces.count, 1)
    }

    /// Reaching the target count tears down bootstrap-only interfaces, which exist to get a
    /// node its first peers and are meant to go away once it has them (`Discovery.py:643-648`).
    func testBootstrapInterfacesAreTornDownOnceTheTargetIsMet() {
        Reticulum.storedMaxAutoconnectedInterfaces = 1

        let bootstrap = MonitoredInterface(name: "bootstrap", online: true)
        bootstrap.bootstrapOnly = true
        transport.register(interface: bootstrap)

        _ = monitored(name: "dialled", online: true)
        discovery.monitorTick()

        XCTAssertFalse(transport.interfaces.contains { ($0 as? MonitoredInterface) === bootstrap },
                       "the bootstrap interface is torn down")
        XCTAssertEqual(discovery.bootstrapInterfaceCount(), 0)
    }

    /// And when every auto-connected interface is down and no bootstrap interface is left, they
    /// come back—otherwise a node that lost its peers has no way to find new ones
    /// (`Discovery.py:650-654`).
    func testLosingEveryPeerReenablesTheBootstrapInterfaces() {
        var reenabled = 0
        discovery.reenableBootstrapInterfaces = { reenabled += 1 }

        let peer = monitored()
        discovery.monitorTick()
        XCTAssertEqual(reenabled, 1)

        // And not while a peer is up, which is what makes the clause conditional rather than a
        // re-enable on every pass.
        peer.isOnline = true
        discovery.monitorTick()
        XCTAssertEqual(reenabled, 1)
    }

    /// A bootstrap interface that's still attached is the node's remaining route, so the
    /// re-enable holds off rather than duplicating it (`Discovery.py:651`).
    func testTheReenableWaitsWhileABootstrapInterfaceIsStillAttached() {
        var reenabled = 0
        discovery.reenableBootstrapInterfaces = { reenabled += 1 }

        let bootstrap = MonitoredInterface(name: "bootstrap")
        bootstrap.bootstrapOnly = true
        transport.register(interface: bootstrap)

        _ = monitored()
        discovery.monitorTick()

        XCTAssertEqual(reenabled, 0)
    }

    // MARK: - Reconnect on startup

    /// Python: `connect_discovered` (`Discovery.py:678-689`), which dials what's already been
    /// persisted so a restart doesn't have to re-hear every peer.
    func testConnectDiscoveredDialsThePersistedEndpoints() {
        var info = discovered()
        info.configEntry = nil
        discovery.interfaceDiscovered(info)

        discovery.connectDiscovered()

        XCTAssertEqual(transport.interfaces.count, 1)
        XCTAssertTrue(discovery.initialAutoconnectRan)
    }
}
