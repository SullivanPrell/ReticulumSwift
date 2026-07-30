import XCTest
@testable import ReticulumSwift

/// `rnstatus` running against its own in-process stack — the standalone / shared-instance
/// path, where there is no RPC hop and `InterfaceStatsPayload.build` supplies the dict
/// directly.
///
/// Python reference: `Reticulum.get_interface_stats()` (`RNS/Reticulum.py:1314-1468`) and
/// `rnstatus.py:340`.
final class RNStatusInProcessTests: XCTestCase {

    final class StubInterface: Interface {
        var name: String
        var bitrate: Int = 9600
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?

        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {}
    }

    private func keys(_ value: MsgPack.Value) -> [String] {
        guard case .map(let pairs) = value else { return [] }
        return pairs.compactMap { $0.0.asString }
    }

    // MARK: - Top-level key order

    func testTopLevelKeyOrderWithTransportDisabled() {
        let transport = Transport()
        transport.transportEnabled = false
        transport.register(interface: StubInterface(name: "stub"))

        // Python: interfaces, rxb, txb, rxs, txs, then rss LAST. The transport block only
        // appears when Reticulum.transport_enabled().
        XCTAssertEqual(keys(InterfaceStatsPayload.build(transport)),
                       ["interfaces", "rxb", "txb", "rxs", "txs", "rss"])
    }

    func testTopLevelKeyOrderWithTransportEnabled() {
        let transport = Transport()
        transport.transportIdentity = Identity()
        transport.transportEnabled = true
        transport.register(interface: StubInterface(name: "stub"))

        // Python: Reticulum.py:1459-1467 — rss is appended AFTER the transport block, and
        // `rnstatus -j` preserves insertion order, so the position is contractual.
        let ordered = keys(InterfaceStatsPayload.build(transport))
        XCTAssertEqual(ordered,
                       ["interfaces", "rxb", "txb", "rxs", "txs",
                        "transport_id", "network_id", "transport_uptime", "probe_responder", "rss"])
        XCTAssertEqual(ordered.last, "rss")
    }

    func testTransportIDIsAbsentNotNilWhenTransportIsDisabled() {
        let transport = Transport()
        transport.transportEnabled = false
        let stats = RNStatusStats(InterfaceStatsPayload.build(transport))!
        // Absence and a nil value render identically, but they differ in -j output.
        XCTAssertNil(stats.raw("transport_id"))
        XCTAssertFalse(stats.hasTransportID)
    }

    func testEmptyPayloadShape() {
        XCTAssertEqual(keys(InterfaceStatsPayload.empty),
                       ["interfaces", "rxb", "txb", "rxs", "txs", "rss"])
        XCTAssertNotNil(RNStatusStats(InterfaceStatsPayload.empty))
    }

    // MARK: - Per-interface shape

    func testInterfaceEntryCarriesEveryKeyRnstatusReads() {
        let transport = Transport()
        transport.register(interface: StubInterface(name: "stub"))
        let stats = RNStatusStats(InterfaceStatsPayload.build(transport))!
        let iface = try! XCTUnwrap(stats.interfaces.first)

        // The unconditional block Python's builder always emits (Reticulum.py:1422-1442).
        for key in ["name", "short_name", "hash", "type", "rxb", "txb",
                    "incoming_announce_frequency", "outgoing_announce_frequency",
                    "incoming_pr_frequency", "outgoing_pr_frequency",
                    "announce_rate_target", "announce_rate_penalty", "announce_rate_grace",
                    "held_announces", "burst_active", "burst_activated",
                    "pr_burst_active", "pr_burst_activated", "status", "mode",
                    "rxs", "txs", "bitrate", "clients"] {
            XCTAssertTrue(iface.has(key), "missing \(key)")
        }
    }

    func testInterfaceHashMatchesPythonGetHash() {
        let transport = Transport()
        let stub = StubInterface(name: "stub")
        transport.register(interface: stub)
        let iface = RNStatusStats(InterfaceStatsPayload.build(transport))!.interfaces[0]
        // Python: Interface.get_hash() = RNS.Identity.full_hash(str(interface).encode())
        XCTAssertEqual(iface.data("hash"), Hashes.fullHash(Data(stub.displayName.utf8)))
    }

    func testSharedInstanceNameTriggersTheServingBranch() {
        let transport = Transport()
        // PosixTCPServer's displayName is the literal "Shared Instance[<port>]"
        // (LocalInterface.py:496-498), which is the prefix rnstatus keys the Serving /
        // subtraction branches off. It no longer depends on the `name` passed here — see
        // `bugs/022`, where building it from `name` made it correct only at this one call site.
        let server = PosixTCPServer(name: "Shared Instance", port: 37428)
        transport.register(interface: server)
        let iface = RNStatusStats(InterfaceStatsPayload.build(transport))!.interfaces[0]
        XCTAssertEqual(iface.name, "Shared Instance[37428]")
        XCTAssertTrue(iface.name.hasPrefix("Shared Instance["))
        transport.deregister(interface: server)
    }

    // MARK: - End to end, offline

    func testInProcessStatsRenderEndToEnd() {
        let transport = Transport()
        transport.transportIdentity = Identity()
        transport.transportEnabled = true
        transport.register(interface: StubInterface(name: "stub"))

        let stats = RNStatusStats(InterfaceStatsPayload.build(transport))
        XCTAssertNotNil(stats)

        var options = RNStatusRenderer.Options()
        options.linkStats = true
        let rendered = RNStatusRenderer(options: options, now: 1_700_000_000)
            .render(stats: stats!, linkCount: 0)
        // The rendered row is the interface's `displayName`, which is class-qualified for every
        // conformer including test doubles since `bugs/022` — not the bare configured `name`.
        XCTAssertTrue(rendered.contains(" StubInterface[stub]\n"))
        XCTAssertTrue(rendered.contains("    Status    : Up\n"))
        XCTAssertTrue(rendered.contains("    Rate      : 9.60 kbps\n"))
        XCTAssertTrue(rendered.contains(" Transport Instance <"))
        XCTAssertTrue(rendered.hasSuffix("\n"))
    }

    func testJSONRoundTripFromTheInProcessBuilder() throws {
        let transport = Transport()
        transport.register(interface: StubInterface(name: "stub"))
        let payload = InterfaceStatsPayload.build(transport)
        let encoded = RNStatusJSON.encode(RNStatusJSON.normaliseStats(payload))
        let object = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
        XCTAssertNotNil(object?["interfaces"] as? [[String: Any]])
        // The 32-byte interface hash must have become undelimited hex, not bytes.
        let iface = (object?["interfaces"] as? [[String: Any]])?.first
        XCTAssertEqual((iface?["hash"] as? String)?.count, 64)
        XCTAssertTrue(encoded.hasSuffix("\"rss\": null}"))
    }
}
