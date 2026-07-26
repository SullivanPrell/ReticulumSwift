import XCTest
@testable import ReticulumSwift

/// RNS 1.4.2 parity.
///
/// The release is three core diffs against 1.4.1 plus changes to `rnsh`, which
/// is not ported. Only one of the three is behavioural, and this port already
/// had it — so rather than a port, 1.4.2 is an audit, and this file is what
/// keeps that audit from silently rotting:
///
///  - `Transport.py:3126` added `if not interface.online: continue` to the
///    recursive path-request fan-out. Covered below.
///  - `Transport.py:1841` moved a gravity-replacement log line from `LOG_DEBUG`
///    to `LOG_PATHING`. This port does not emit that line, so there is nothing
///    to assert.
///  - `Discovery.py` began caching the blackholed identity set for 60s in
///    `list_discovered_interfaces`. Python pays an RPC round-trip to the shared
///    instance per `is_blackholed` call; `Transport.isBlackholed` is a
///    dictionary lookup under a lock, so caching would buy nothing and would
///    delay a fresh blackhole by up to a minute. Covered below by asserting the
///    property the cache would have cost us.
final class RNS142ParityTests: XCTestCase {

    /// Mock interface with a settable `isOnline`, so an interface can be taken
    /// down without being deregistered — which is the state Python 1.4.2's new
    /// guard exists for.
    final class ToggleableInterface: Interface {
        var name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        var mode: InterfaceMode = .full
        var recursivePrs: Bool = false
        init(name: String) { self.name = name }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    private func pathRequest(for destination: Data, via transportID: Data, tag: UInt8) -> Packet {
        let body = destination + transportID + Data(repeating: tag, count: 16)
        return Packet(destinationType: .plain, packetType: .data,
                      destinationHash: Transport.pathRequestDestinationHash, data: body)
    }

    private func pathRequests(on iface: ToggleableInterface) -> [Packet] {
        iface.sent.filter {
            $0.destinationType == .plain && $0.destinationHash == Transport.pathRequestDestinationHash
        }
    }

    // MARK: - Recursive path requests skip offline interfaces

    /// Control: an online egress interface does receive the recursive request,
    /// so the negative test below is measuring the offline flag and not a
    /// fixture that never forwards anything.
    func testRecursivePathRequestReachesAnOnlineInterface() throws {
        let t = Transport()
        t.transportEnabled = true

        let ingress = ToggleableInterface(name: "ingress")
        ingress.recursivePrs = true
        let egress = ToggleableInterface(name: "egress")
        t.register(interface: ingress)
        t.register(interface: egress)

        ingress.inboundHandler?(pathRequest(for: Data(repeating: 0x91, count: 16),
                                            via: t.transportInstanceID, tag: 0x01), ingress)

        XCTAssertGreaterThan(pathRequests(on: egress).count, 0,
            "an online interface must receive the recursive path request")
    }

    /// RNS 1.4.2: a registered but offline interface is skipped. Sending down a
    /// dead interface is a request that can never be answered, and on a
    /// reconnecting transport it is also a write into a socket that is being
    /// torn down.
    func testRecursivePathRequestSkipsAnOfflineInterface() throws {
        let t = Transport()
        t.transportEnabled = true

        let ingress = ToggleableInterface(name: "ingress")
        ingress.recursivePrs = true
        let offline = ToggleableInterface(name: "offline")
        offline.isOnline = false
        t.register(interface: ingress)
        t.register(interface: offline)

        ingress.inboundHandler?(pathRequest(for: Data(repeating: 0x92, count: 16),
                                            via: t.transportInstanceID, tag: 0x02), ingress)

        XCTAssertEqual(pathRequests(on: offline).count, 0,
            "an offline interface must not be asked to carry a recursive path request")
    }

    // MARK: - Blackholing a discovery source applies immediately

    /// The property Python traded away for its 60-second cache. `InterfaceDiscovery`
    /// re-checks the blackhole list on every listing, so an identity blackholed
    /// now is gone from the next listing rather than up to a minute later.
    func testBlackholingRemovesADiscoveredInterfaceOnTheNextListing() throws {
        let t = Transport()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns142-discovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = InterfaceDiscovery(storagePath: dir.path)
        discovery.isBlackholed = { [weak t] hash in t?.isBlackholed(hash) ?? false }

        let transportID = Data(repeating: 0xA1, count: 16)
        let networkID   = Data(repeating: 0xB2, count: 16)
        let transportHex = RNSUtilities.hexrep(transportID, delimit: false)
        let name = "BLACKHOLE TARGET"
        let now = Date().timeIntervalSince1970
        let info = DiscoveredInterfaceInfo(
            type: "BackboneInterface", transport: true, name: name,
            received: now, stamp: Data(repeating: 0, count: 32), value: 14,
            transportID: transportHex,
            networkID: RNSUtilities.hexrep(networkID, delimit: false),
            hops: 1,
            latitude: nil, longitude: nil, height: nil,
            ifacNetname: nil, ifacNetkey: nil,
            reachableOn: "127.0.0.1", port: 4242,
            frequency: nil, bandwidth: nil, sf: nil, cr: nil,
            modulation: nil, channel: nil,
            configEntry: "[[\(name)]]\n  type = BackboneInterface",
            discoveryHash: Hashes.fullHash(Data((transportHex + name).utf8)),
            discovered: now, lastHeard: now, heardCount: 0,
            status: nil, statusCode: nil
        )
        discovery.interfaceDiscovered(info)

        XCTAssertEqual(discovery.listDiscoveredInterfaces().count, 1,
                       "the discovery should be listed before its identity is blackholed")

        _ = t.blackholeIdentity(transportID, until: nil, reason: nil)

        XCTAssertEqual(discovery.listDiscoveredInterfaces().count, 0,
            "blackholing a transport identity must drop its discovery from the very next "
            + "listing; Python's 60s cache is an RPC optimisation this port does not need")
    }
}
