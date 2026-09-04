import XCTest
@testable import ReticulumSwift

/// The counters behind the interface-stats keys must actually move.
///
/// Emitting a key is half the contract. A key that's always zero reads as "this interface
/// has seen no violations" rather than "this port never counts them", and the two are
/// indistinguishable to an operator running `rnstatus` against a Swift daemon. These tests
/// drive real frames through the inbound funnel and assert the published numbers change.
final class InterfaceStatsCounterTests: XCTestCase {

    private static let dstLen = Constants.truncatedHashLength

    private func statsForFirstInterface(_ t: Transport) throws -> [String: MsgPack.Value] {
        let payload = InterfaceStatsPayload.build(t)
        let interfaces = try XCTUnwrap(payload.asDictionary?["interfaces"]?.asArray)
        return try XCTUnwrap(interfaces.first?.asDictionary)
    }

    // MARK: - Protocol violations

    func testAMalformedFrameIsCounted() throws {
        let t = Transport()
        let iface = UDPInterface(name: "in", listenPort: 4242, forwardPort: 4243)
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        XCTAssertEqual(try statsForFirstInterface(t)["protocol_violations"]?.asInt, 0,
                       "nothing has arrived yet")

        // Two bytes is a flags/hops pair and nothing else: no destination hash, so `unpack`
        // rejects it. Python: `protocol_violation(f"Malformed packet ({len(raw)} bytes)")`
        // (`Transport.py:1794`).
        iface.rawInboundHandler?(Data([0x00, 0x00]), iface)

        XCTAssertEqual(try statsForFirstInterface(t)["protocol_violations"]?.asInt, 1,
                       "a frame that cannot be unpacked is a counted violation, not a "
                       + "silent drop")
    }

    func testAnOversizedAnnounceIsCounted() throws {
        let t = Transport()
        let iface = UDPInterface(name: "in", listenPort: 4242, forwardPort: 4243)
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        // A structurally valid announce whose frame exceeds the protocol MTU. Python:
        // `protocol_violation("Excessive announce packet frame size ...")`
        // (`Transport.py:1804`).
        var raw = Data([0x01, 0x00])                                  // flags: ANNOUNCE, hop 0
        raw.append(Data(repeating: 0xAB, count: Self.dstLen))         // destination hash
        raw.append(Data([0x00]))                                      // context
        raw.append(Data(repeating: 0x5A, count: Constants.mtu + 1))   // payload past the MTU
        iface.rawInboundHandler?(raw, iface)

        XCTAssertEqual(try statsForFirstInterface(t)["protocol_violations"]?.asInt, 1,
                       "an announce past the protocol MTU is an amplification path, and "
                       + "Python counts the drop")
    }

    func testViolationsAccumulateRatherThanLatch() throws {
        let t = Transport()
        let iface = UDPInterface(name: "in", listenPort: 4242, forwardPort: 4243)
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        for _ in 0..<3 { iface.rawInboundHandler?(Data([0x00, 0x00]), iface) }

        XCTAssertEqual(try statsForFirstInterface(t)["protocol_violations"]?.asInt, 3,
                       "a counter written as a flag would report 1 here")
    }

    // MARK: - Announce and path-request totals

    func testAnnounceCountersRecordFrameSizeNotJustFrequency() throws {
        let t = Transport()
        let iface = UDPInterface(name: "in", listenPort: 4242, forwardPort: 4243)
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        // Python bumps `arxc`/`arxb` inside the same `received_announce` that appends to the
        // frequency deque (`Interface.py:302`), so the two can't drift apart.
        t.notifyIncomingAnnounce(on: iface, size: 140)
        t.notifyIncomingAnnounce(on: iface, size: 60)

        let stats = try statsForFirstInterface(t)
        XCTAssertEqual(stats["arxc"]?.asInt, 2, "two announces arrived")
        XCTAssertEqual(stats["arxb"]?.asInt, 200,
                       "bytes accumulate; a count-only implementation reports 2 here")
    }

    func testPathRequestCountersAreSeparateFromAnnounceCounters() throws {
        let t = Transport()
        let iface = UDPInterface(name: "in", listenPort: 4242, forwardPort: 4243)
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        t.notifyIncomingAnnounce(on: iface, size: 100)
        t.notifyOutgoingPathRequest(on: iface, size: 37)

        let stats = try statsForFirstInterface(t)
        XCTAssertEqual(stats["arxb"]?.asInt, 100)
        XCTAssertEqual(stats["ptxb"]?.asInt, 37)
        XCTAssertEqual(stats["prxb"]?.asInt, 0, "nothing inbound was a path request")
        XCTAssertEqual(stats["atxb"]?.asInt, 0, "nothing outbound was an announce")
    }

    func testCountersArePerInterface() throws {
        let t = Transport()
        let a = UDPInterface(name: "a", listenPort: 4244, forwardPort: 4245)
        let b = UDPInterface(name: "b", listenPort: 4246, forwardPort: 4247)
        t.register(interface: a)
        t.register(interface: b)
        defer { t.deregister(interface: a); t.deregister(interface: b) }

        t.notifyIncomingAnnounce(on: a, size: 90)

        let payload = InterfaceStatsPayload.build(t)
        let interfaces = try XCTUnwrap(payload.asDictionary?["interfaces"]?.asArray)
        let byName = Dictionary(uniqueKeysWithValues: interfaces.compactMap { entry -> (String, [String: MsgPack.Value])? in
            guard let d = entry.asDictionary, let n = d["short_name"]?.asString else { return nil }
            return (n, d)
        })
        XCTAssertEqual(byName["a"]?["arxb"]?.asInt, 90)
        XCTAssertEqual(byName["b"]?["arxb"]?.asInt, 0,
                       "a shared counter would report 90 on both interfaces")
    }

    // MARK: - packet_filter_hits

    func testADuplicatePacketCountsAsAPacketFilterHit() throws {
        // `if not Transport.packet_filter(packet): return interface.packet_filter_hit()`
        // (`Transport.py:1795`). The live filter in this port is `filterAndRecord`, so the
        // counter has to sit on its inbound `guard`—`packetFilter` is a partial duplicate
        // that no production path calls, and counting there would leave the key at 0 forever.
        let t = Transport()
        let iface = UDPInterface(name: "Filter Hits", listenPort: 4266, forwardPort: 4267)
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        let packet = Packet(destinationType: .single,
                            packetType: .data,
                            destinationHash: Data(repeating: 0x5C, count: 16),
                            context: .none,
                            data: Data(repeating: 0xC5, count: 8))

        t.handleIncoming(packet: packet, from: iface)
        XCTAssertEqual(t.interfaceCounts(for: iface).packetFilterHits, 0,
                       "the first sighting passes the filter, so nothing is filtered yet")

        t.handleIncoming(packet: packet, from: iface)
        XCTAssertEqual(t.interfaceCounts(for: iface).packetFilterHits, 1,
                       """
                       the replay is dropped by the hashlist, which is precisely what \
                       `packet_filter_hits` reports. A key emitted but never incremented \
                       tells a Python operator this interface has seen no filtered traffic, \
                       which is a wrong answer rather than a missing one.
                       """)
    }

    func testPacketFilterHitsAreSeparateFromProtocolViolations() throws {
        // A filtered duplicate isn't malformed. Python increments two different counters and
        // `rnstatus` prints them on separate lines, so folding one into the other would
        // misattribute ordinary replay suppression as peer misbehaviour.
        let t = Transport()
        let iface = UDPInterface(name: "Filter Split", listenPort: 4268, forwardPort: 4269)
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        let packet = Packet(destinationType: .single,
                            packetType: .data,
                            destinationHash: Data(repeating: 0x6D, count: 16),
                            context: .none,
                            data: Data(repeating: 0xD6, count: 8))
        t.handleIncoming(packet: packet, from: iface)
        t.handleIncoming(packet: packet, from: iface)

        let counts = t.interfaceCounts(for: iface)
        XCTAssertEqual(counts.packetFilterHits, 1)
        XCTAssertEqual(counts.protocolViolations, 0,
                       "a duplicate is well-formed; only malformed frames are violations")
    }
}
