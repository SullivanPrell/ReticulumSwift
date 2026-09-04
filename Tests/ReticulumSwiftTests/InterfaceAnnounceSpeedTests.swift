import XCTest
@testable import ReticulumSwift

/// The four announce and path-request speed gauges `rnstatus` reads as `arxs`, `atxs`,
/// `prxs` and `ptxs`.
///
/// Python derives all six speeds in one pass of `count_traffic_loop`
/// (`Transport.py:605-640`): each is `(bytes_now - bytes_at_last_sample) * 8 / seconds`,
/// off the same `transport_traffic_counter` snapshot that produces `rxs` and `txs`. They
/// aren't independent measurements—they're the derivative of the `arxb`/`atxb`/`prxb`/
/// `ptxb` totals this port already accumulates.
///
/// Emitting a constant zero for them would be worse than omitting them: an operator would
/// see `arxb` climbing in the same listing that reports no announce throughput at all.
final class InterfaceAnnounceSpeedTests: XCTestCase {

    private func makeTransport() -> (Transport, UDPInterface) {
        let t = Transport()
        let iface = UDPInterface(name: "Speed Gauges", listenPort: 4272, forwardPort: 4273)
        t.register(interface: iface)
        return (t, iface)
    }

    func testAnnounceSpeedIsTheDerivativeOfTheAnnounceByteTotal() {
        let (t, iface) = makeTransport()
        defer { t.deregister(interface: iface) }

        // First pass only seeds the baseline—Python's `else` branch installs
        // `transport_traffic_counter` and computes nothing.
        t.sampleInterfaceSpeeds(now: 1_000)
        XCTAssertEqual(t.currentAnnounceRxSpeed(for: iface), 0,
                       "a single sample has no interval to divide by")

        t.notifyIncomingAnnounce(on: iface, size: 250)
        t.sampleInterfaceSpeeds(now: 1_010)

        XCTAssertEqual(t.currentAnnounceRxSpeed(for: iface), 200, accuracy: 0.001,
                       "250 bytes over 10 s is (250*8)/10 = 200 bits/s, the same "
                       + "bytes*8/seconds Python applies to rxs (Transport.py:618-620)")
    }

    func testEachGaugeTracksItsOwnCounter() {
        let (t, iface) = makeTransport()
        defer { t.deregister(interface: iface) }
        t.sampleInterfaceSpeeds(now: 2_000)

        t.notifyIncomingAnnounce(on: iface, size: 100)
        t.notifyOutgoingAnnounce(on: iface, size: 200)
        t.notifyIncomingPathRequest(on: iface, size: 300)
        t.notifyOutgoingPathRequest(on: iface, size: 400)
        t.sampleInterfaceSpeeds(now: 2_008)

        // Distinct sizes over one interval, so any pair of gauges reading the same
        // counter is visible here rather than averaging out.
        XCTAssertEqual(t.currentAnnounceRxSpeed(for: iface), 100, accuracy: 0.001)
        XCTAssertEqual(t.currentAnnounceTxSpeed(for: iface), 200, accuracy: 0.001)
        XCTAssertEqual(t.currentPathRequestRxSpeed(for: iface), 300, accuracy: 0.001)
        XCTAssertEqual(t.currentPathRequestTxSpeed(for: iface), 400, accuracy: 0.001)
    }

    func testAQuietIntervalReportsZeroRatherThanTheLastRate() {
        let (t, iface) = makeTransport()
        defer { t.deregister(interface: iface) }
        t.sampleInterfaceSpeeds(now: 3_000)
        t.notifyIncomingAnnounce(on: iface, size: 500)
        t.sampleInterfaceSpeeds(now: 3_010)
        XCTAssertEqual(t.currentAnnounceRxSpeed(for: iface), 400, accuracy: 0.001)

        t.sampleInterfaceSpeeds(now: 3_020)
        XCTAssertEqual(t.currentAnnounceRxSpeed(for: iface), 0, accuracy: 0.001,
                       """
                       Python assigns the new rate unconditionally each pass, so an idle \
                       interval reads zero. A gauge that latched its last value would show \
                       steady announce traffic on a link that has gone silent—the reading \
                       an operator would use to conclude the link is still healthy.
                       """)
    }

    func testThePayloadPublishesTheGaugesRatherThanAConstant() throws {
        let (t, iface) = makeTransport()
        defer { t.deregister(interface: iface) }
        t.sampleInterfaceSpeeds(now: 4_000)
        t.notifyOutgoingAnnounce(on: iface, size: 125)
        t.sampleInterfaceSpeeds(now: 4_010)

        let payload = InterfaceStatsPayload.build(t)
        let interfaces = try XCTUnwrap(payload.asDictionary?["interfaces"]?.asArray)
        let entry = try XCTUnwrap(interfaces.first?.asDictionary)

        XCTAssertEqual(try XCTUnwrap(entry["atxs"]?.asDouble), 100, accuracy: 0.001,
                       "the emitted key must carry the computed gauge; a hardcoded 0 here "
                       + "contradicts the atxb total published beside it")
        XCTAssertEqual(try XCTUnwrap(entry["atxb"]?.asInt), 125,
                       "and the total it is derived from must agree")
    }
}
