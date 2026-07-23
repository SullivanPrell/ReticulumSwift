import XCTest
@testable import ReticulumSwift

/// Pins the exact response shape of the `/path` remote-management handler.
///
/// Python reference: `RNS/Transport.py`, `remote_path_handler`, which returns the
/// entries produced by `Reticulum.get_path_table()` / `get_rate_table()` verbatim
/// (`RNS/Reticulum.py:1470-1508`).
///
/// This matters because `rnpath -R` indexes the returned dictionaries directly:
/// ```python
/// print(... + path["interface"] + " expires " + RNS.timestamp_str(path["expires"]))
/// hour_rate = round(len(entry["timestamps"])/span_hours, 3)
/// ```
/// so any key the Swift handler omits becomes a `KeyError` in the Python client
/// rather than a graceful degradation.
final class RemotePathHandlerShapeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Reticulum.remoteManagementEnabled_ = true
    }

    override func tearDown() {
        Reticulum.remoteManagementEnabled_ = false
        super.tearDown()
    }

    private func makeTransport() throws -> Transport {
        let transport = Transport()
        transport.transportIdentity = Identity()
        try transport.start()
        return transport
    }

    private func invokePathHandler(_ transport: Transport, request: [MsgPack.Value]) throws -> [MsgPack.Value] {
        let mgmt = try XCTUnwrap(transport.remoteManagementDestination)
        let pathHash = Hashes.truncatedHash(Data("/path".utf8))
        let entry = try XCTUnwrap(mgmt.requestHandlers[pathHash])
        let response = try XCTUnwrap(
            entry.handler(pathHash, MsgPack.encode(.array(request)), Data(), makeMinimalLink(), 0)
        )
        return try XCTUnwrap(MsgPack.decode(response).asArray)
    }

    /// An interface that declares an announce-rate target, so that
    /// `isAnnounceRateBlocked` seeds a rate-table entry instead of short-circuiting.
    final class RateTargetInterface: Interface {
        var name: String
        var bitrate: Int = 100_000
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var announceRateTarget: TimeInterval?

        init(name: String, rateTarget: TimeInterval) {
            self.name = name
            self.announceRateTarget = rateTarget
        }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {}
    }

    /// A link object is required by the handler signature but never inspected by it.
    private func makeMinimalLink() -> Link {
        let identity = Identity()
        let destination = try! Destination(identity: identity, direction: .in, kind: .single,
                                           appName: "dummy", aspects: ["link"])
        let transport = Transport()
        transport.register(interface: LoopbackInterface(name: "PathShapeTest"))
        return try! Link.initiate(destination: destination, transport: transport)
    }

    private func addPath(_ transport: Transport, hops: UInt8, interface: String) -> Data {
        let destination = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        transport.restore(path: Transport.PathEntry(
            destinationHash: destination,
            nextHopInterfaceName: interface,
            hops: hops,
            lastHeard: Date(),
            identityHash: Data(repeating: 0x01, count: 16),
            nextHopTransportID: Data(repeating: 0x02, count: 16)
        ), forDestination: destination)
        return destination
    }

    // MARK: - table

    func testTableEntryCarriesEveryKeyPythonProduces() throws {
        // Python get_path_table entry:
        //   {"hash", "timestamp", "via", "hops", "expires", "interface"}
        let transport = try makeTransport()
        _ = addPath(transport, hops: 2, interface: "TCPInterface[example:4242]")

        let entries = try invokePathHandler(transport, request: [.string("table")])
        let fields = try XCTUnwrap(entries.first?.asDictionary)

        XCTAssertNotNil(fields["hash"])
        XCTAssertNotNil(fields["timestamp"], "rnpath's JSON mode serialises every key")
        XCTAssertNotNil(fields["via"])
        XCTAssertNotNil(fields["hops"])
        XCTAssertNotNil(fields["expires"])
        XCTAssertNotNil(fields["interface"], "rnpath prints path[\"interface\"] directly")
    }

    func testTableEntryInterfaceNameMatchesPath() throws {
        let transport = try makeTransport()
        _ = addPath(transport, hops: 1, interface: "TCPInterface[example:4242]")

        let entries = try invokePathHandler(transport, request: [.string("table")])
        let fields = try XCTUnwrap(entries.first?.asDictionary)
        XCTAssertEqual(fields["interface"]?.asString, "TCPInterface[example:4242]")
    }

    func testTableHonoursMaxHops() throws {
        // Python: data[2] is max_hops, passed to get_path_table(max_hops=max_hops).
        let transport = try makeTransport()
        _ = addPath(transport, hops: 1, interface: "A")
        _ = addPath(transport, hops: 5, interface: "B")

        let unfiltered = try invokePathHandler(transport, request: [.string("table")])
        XCTAssertEqual(unfiltered.count, 2)

        let limited = try invokePathHandler(transport, request: [.string("table"), .nil, .uint(2)])
        XCTAssertEqual(limited.count, 1, "max_hops = 2 should exclude the 5-hop path")
        XCTAssertEqual(limited.first?.asDictionary?["hops"]?.asInt, 1)
    }

    func testTableFiltersByDestinationHash() throws {
        let transport = try makeTransport()
        let wanted = addPath(transport, hops: 1, interface: "A")
        _ = addPath(transport, hops: 1, interface: "B")

        let entries = try invokePathHandler(transport, request: [.string("table"), .bytes(wanted)])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.asDictionary?["hash"]?.asData, wanted)
    }

    // MARK: - rates

    func testRatesEntryCarriesEveryKeyPythonProduces() throws {
        // Python get_rate_table entry:
        //   {"hash", "last", "rate_violations", "blocked_until", "timestamps"}
        let transport = try makeTransport()
        let destination = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        // Seed a rate-table entry the same way an inbound announce would.
        let iface = RateTargetInterface(name: "RateTest", rateTarget: 3600)
        transport.register(interface: iface)
        _ = transport.isAnnounceRateBlocked(destinationHash: destination, interface: iface)

        let mgmt = try XCTUnwrap(transport.remoteManagementDestination)
        let pathHash = Hashes.truncatedHash(Data("/path".utf8))
        let entry = try XCTUnwrap(mgmt.requestHandlers[pathHash])
        let response = try XCTUnwrap(
            entry.handler(pathHash, MsgPack.encode(.array([.string("rates")])), Data(), makeMinimalLink(), 0)
        )
        let entries = try XCTUnwrap(MsgPack.decode(response).asArray)
        let fields = try XCTUnwrap(entries.first?.asDictionary)

        XCTAssertNotNil(fields["hash"])
        XCTAssertNotNil(fields["last"])
        XCTAssertNotNil(fields["rate_violations"])
        XCTAssertNotNil(fields["blocked_until"])
        XCTAssertNotNil(fields["timestamps"], "rnpath derives the announce rate from timestamps")
        XCTAssertNotNil(fields["timestamps"]?.asArray)
    }

    // MARK: - /status

    private func invokeStatusHandler(_ transport: Transport, includeLinkStats: Bool) throws -> [MsgPack.Value] {
        let mgmt = try XCTUnwrap(transport.remoteManagementDestination)
        let statusHash = Hashes.truncatedHash(Data("/status".utf8))
        let entry = try XCTUnwrap(mgmt.requestHandlers[statusHash])
        let request = MsgPack.encode(.array([.bool(includeLinkStats)]))
        let response = try XCTUnwrap(entry.handler(statusHash, request, Data(), makeMinimalLink(), 0))
        return try XCTUnwrap(MsgPack.decode(response).asArray)
    }

    func testStatusReturnsTheFullInterfaceStatsPayload() throws {
        // Python: response.append(Transport.owner.get_interface_stats()) — the whole dict,
        // which rnstatus then indexes by "interfaces", "rxb", "txs" and so on. Returning a
        // summarised list of per-interface names would leave rnstatus -R with nothing to read.
        let transport = try makeTransport()
        let entries = try invokeStatusHandler(transport, includeLinkStats: false)
        XCTAssertEqual(entries.count, 1, "no link count requested")

        let stats = try XCTUnwrap(entries[0].asDictionary)
        XCTAssertNotNil(stats["interfaces"]?.asArray)
        XCTAssertNotNil(stats["rxb"])
        XCTAssertNotNil(stats["txb"])
        XCTAssertNotNil(stats["rxs"])
        XCTAssertNotNil(stats["txs"])
    }

    func testStatusAppendsLinkCountWhenRequested() throws {
        // Python: if data[0] == True: response.append(Transport.owner.get_link_count())
        let transport = try makeTransport()
        let entries = try invokeStatusHandler(transport, includeLinkStats: true)
        XCTAssertEqual(entries.count, 2)
        XCTAssertNotNil(entries[1].asInt)
    }

    func testStatusInterfaceEntriesCarryPerInterfaceKeys() throws {
        let transport = try makeTransport()
        transport.register(interface: LoopbackInterface(name: "StatusShapeTest"))

        let entries = try invokeStatusHandler(transport, includeLinkStats: false)
        let stats = try XCTUnwrap(entries[0].asDictionary)
        let interfaces = try XCTUnwrap(stats["interfaces"]?.asArray)
        let iface = try XCTUnwrap(interfaces.first?.asDictionary)

        // A representative sample of the keys rnstatus reads off each interface.
        for key in ["name", "short_name", "hash", "type", "rxb", "txb", "status",
                    "mode", "bitrate", "rxs", "txs", "announce_queue", "clients"] {
            XCTAssertNotNil(iface[key], "interface stats should carry \"\(key)\"")
        }
    }

    // MARK: - Unknown commands

    func testUnknownCommandReturnsNil() throws {
        let transport = try makeTransport()
        let mgmt = try XCTUnwrap(transport.remoteManagementDestination)
        let pathHash = Hashes.truncatedHash(Data("/path".utf8))
        let entry = try XCTUnwrap(mgmt.requestHandlers[pathHash])
        let response = entry.handler(pathHash,
                                     MsgPack.encode(.array([.string("nonsense")])),
                                     Data(), makeMinimalLink(), 0)
        XCTAssertNil(response)
    }
}
