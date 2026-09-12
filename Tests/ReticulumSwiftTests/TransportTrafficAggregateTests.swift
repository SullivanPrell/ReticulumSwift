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

/// The transport-level traffic aggregates Python publishes as `arxb`, `atxb`, `arxs`,
/// `atxs`, `arxf`, `atxf`, `prxb`, `ptxb`, `prxs`, `ptxs`, `prxf`, `ptxf`, `rxpps` and
/// `txpps` (`Reticulum.py:1578-1597`).
///
/// Python derives every one of them in a single pass of `count_traffic_loop`
/// (`Transport.py:600-671`), from the same per-interface counters this port already keeps.
/// They are sums across interfaces, not a second set of measurements—so the thing worth
/// pinning is that each aggregate reads its own per-interface counter and spans every
/// registered interface.
///
/// `rnstatus` indexes `stats["rxpps"]` and the announce/path-request totals **without a
/// presence guard** (`rnstatus.py:740`, `:748`), so a daemon that omits them makes the
/// peer's own tool raise `KeyError` and print nothing at all—the same failure mode the
/// missing `txdrp` key produced.
final class TransportTrafficAggregateTests: XCTestCase {

    private func makeTransport(_ names: [String]) -> (Transport, [UDPInterface]) {
        let t = Transport()
        var made: [UDPInterface] = []
        for (offset, name) in names.enumerated() {
            let iface = UDPInterface(name: name,
                                     listenPort: UInt16(4400 + offset * 2),
                                     forwardPort: UInt16(4401 + offset * 2))
            t.register(interface: iface)
            made.append(iface)
        }
        return (t, made)
    }

    // MARK: - Byte totals

    func testAnnounceByteTotalsSumEveryInterface() {
        let (t, ifaces) = makeTransport(["Agg A", "Agg B"])
        defer { ifaces.forEach { t.deregister(interface: $0) } }
        t.sampleInterfaceSpeeds(now: 1_000)

        t.notifyIncomingAnnounce(on: ifaces[0], size: 100)
        t.notifyIncomingAnnounce(on: ifaces[1], size: 250)
        t.notifyOutgoingAnnounce(on: ifaces[0], size: 40)
        t.sampleInterfaceSpeeds(now: 1_010)

        XCTAssertEqual(t.announceRxBytes, 350,
                       "`Transport.announce_rxb += arxb`, where arxb accumulates every "
                       + "interface's diff in the same pass (Transport.py:664)")
        XCTAssertEqual(t.announceTxBytes, 40,
                       "the outbound total reads `atxb`, not `arxb`—distinct sizes here so "
                       + "a gauge wired to the wrong counter can't average out")
    }

    func testPathRequestByteTotalsAreSeparateFromAnnounces() {
        let (t, ifaces) = makeTransport(["Agg C"])
        defer { ifaces.forEach { t.deregister(interface: $0) } }
        t.sampleInterfaceSpeeds(now: 2_000)

        t.notifyIncomingAnnounce(on: ifaces[0], size: 111)
        t.notifyIncomingPathRequest(on: ifaces[0], size: 222)
        t.notifyOutgoingPathRequest(on: ifaces[0], size: 333)
        t.sampleInterfaceSpeeds(now: 2_010)

        XCTAssertEqual(t.prRxBytes, 222)
        XCTAssertEqual(t.prTxBytes, 333)
        XCTAssertEqual(t.announceRxBytes, 111,
                       "announce and path-request totals must not feed each other")
    }

    func testByteTotalsAccumulateAcrossSamplingPasses() {
        let (t, ifaces) = makeTransport(["Agg D"])
        defer { ifaces.forEach { t.deregister(interface: $0) } }
        t.sampleInterfaceSpeeds(now: 3_000)

        t.notifyIncomingAnnounce(on: ifaces[0], size: 60)
        t.sampleInterfaceSpeeds(now: 3_010)
        t.notifyIncomingAnnounce(on: ifaces[0], size: 40)
        t.sampleInterfaceSpeeds(now: 3_020)

        XCTAssertEqual(t.announceRxBytes, 100,
                       """
                       Python uses `+=` on the transport total and only ever adds the diff \
                       since the last sample (Transport.py:664). A total that assigned the \
                       interval's bytes instead would report 40 here—the last interval, \
                       presented as the lifetime total.
                       """)
    }

    // MARK: - Aggregate speeds

    func testAggregateAnnounceSpeedIsTheSumOfThePerInterfaceGauges() {
        let (t, ifaces) = makeTransport(["Agg E", "Agg F"])
        defer { ifaces.forEach { t.deregister(interface: $0) } }
        t.sampleInterfaceSpeeds(now: 4_000)

        t.notifyIncomingAnnounce(on: ifaces[0], size: 100)   // 80 bits/s over 10 s
        t.notifyIncomingAnnounce(on: ifaces[1], size: 200)   // 160 bits/s over 10 s
        t.notifyOutgoingPathRequest(on: ifaces[1], size: 50) // 40 bits/s over 10 s
        t.sampleInterfaceSpeeds(now: 4_010)

        XCTAssertEqual(t.announceSpeedRx, 240, accuracy: 0.001,
                       "80 + 160: `arxs += carxs` inside the per-interface loop "
                       + "(Transport.py:621)")
        XCTAssertEqual(t.announceSpeedTx, 0, accuracy: 0.001)
        XCTAssertEqual(t.prSpeedTx, 40, accuracy: 0.001)
    }

    func testAggregateSpeedsAreReassignedEachPassRatherThanAccumulated() {
        let (t, ifaces) = makeTransport(["Agg G"])
        defer { ifaces.forEach { t.deregister(interface: $0) } }
        t.sampleInterfaceSpeeds(now: 5_000)
        t.notifyIncomingAnnounce(on: ifaces[0], size: 500)
        t.sampleInterfaceSpeeds(now: 5_010)
        XCTAssertEqual(t.announceSpeedRx, 400, accuracy: 0.001)

        t.sampleInterfaceSpeeds(now: 5_020)
        XCTAssertEqual(t.announceSpeedRx, 0, accuracy: 0.001,
                       """
                       `Transport.announce_speed_rx = arxs` is an assignment, unlike the \
                       byte totals directly above it (Transport.py:666). A gauge that \
                       accumulated would show announce throughput on a network that has \
                       gone quiet.
                       """)
    }

    // MARK: - Aggregate frequencies

    func testAggregateFrequenciesSumThePerInterfaceFrequencies() {
        let (t, ifaces) = makeTransport(["Agg H", "Agg I"])
        defer { ifaces.forEach { t.deregister(interface: $0) } }

        // `incoming_announce_frequency()` needs more than IC_DEQUE_MIN_SAMPLE samples
        // before it reports anything, so three announces per interface.
        for iface in ifaces {
            t.notifyIncomingAnnounce(on: iface, at: 6_000, size: 10)
            t.notifyIncomingAnnounce(on: iface, at: 6_001, size: 10)
            t.notifyIncomingAnnounce(on: iface, at: 6_002, size: 10)
        }
        t.sampleInterfaceSpeeds(now: 6_003)

        // Each interface reports n/(now - oldest) = 3/(6_003 - 6_000) = 1 Hz, computed
        // from Python's formula rather than by asking the tracker, so a tracker that
        // changed its arithmetic would fail here instead of agreeing with itself.
        XCTAssertEqual(t.announceFreqRx, 2, accuracy: 0.001,
                       "`iafreq += interface.incoming_announce_frequency()` across the "
                       + "interface loop (Transport.py:626): 1 Hz on each of two interfaces")
        XCTAssertEqual(t.announceFreqTx, 0, accuracy: 0.001)
        XCTAssertEqual(t.prFreqRx, 0, accuracy: 0.001)
    }

    // MARK: - Packet counters and packets per second

    func testInboundPacketsAreCounted() throws {
        let t = Transport()
        let iface = RecordingInterface(name: "Agg RX")
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        XCTAssertEqual(t.rxPackets, 0)
        t.handleIncoming(packet: Self.plainPacket(), from: iface)
        t.handleIncoming(packet: Self.plainPacket(byte: 0x02), from: iface)

        XCTAssertEqual(t.rxPackets, 2,
                       "`Transport.rx_packets += 1` once per admitted inbound frame "
                       + "(Transport.py:1798)")
    }

    func testOutboundPacketsAreCounted() throws {
        let t = Transport()
        let iface = RecordingInterface(name: "Agg TX")
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        _ = try t.send(Self.plainPacket())

        XCTAssertEqual(iface.sent.count, 1, "the fixture has to reach the wire")
        XCTAssertEqual(t.txPackets, 1,
                       """
                       `Transport.tx_packets += 1` after a successful `process_outgoing` \
                       (Transport.py:1329). Python counts this in one place because every \
                       send funnels through `Transport.transmit`; a port that counted at \
                       each call site would miss whichever site it forgot.
                       """)
    }

    func testAFilteredDuplicateIsNotCountedAsReceived() {
        let t = Transport()
        let iface = RecordingInterface(name: "Agg Dup")
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        // A SINGLE destination, because that's what reaches the duplicate check. Python
        // answers `True` for a PLAIN packet below the hop ceiling without ever consulting
        // the hashlist (`Transport.py:1654-1655`), so a replayed PLAIN frame *is* received
        // traffic and this test would be asserting the opposite of upstream.
        t.handleIncoming(packet: Self.singlePacket(), from: iface)
        t.handleIncoming(packet: Self.singlePacket(), from: iface)

        XCTAssertEqual(t.rxPackets, 1,
                       """
                       Python increments `rx_packets` after `packet_filter(packet)` returns \
                       true (Transport.py:1795-1798), so a replayed frame is a filter hit \
                       rather than received traffic. Counting at the top of `inbound` would \
                       inflate `rxpps` on exactly the noisiest links, where duplicates are \
                       most of what arrives.
                       """)
    }

    func testPacketsPerSecondIsTheDeltaOverTheInterval() {
        let t = Transport()
        let iface = RecordingInterface(name: "Agg PPS")
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }
        t.startTime = 7_000

        // Distinct payloads: identical frames are duplicates, and the counter deliberately
        // sits behind the duplicate filter (see the test below).
        for i in 0 ..< 20 { t.handleIncoming(packet: Self.plainPacket(byte: UInt8(i)), from: iface) }
        t.sampleInterfaceSpeeds(now: 7_010)

        XCTAssertEqual(t.rxPPS, 2,
                       "20 packets over the 10 s since transport start: "
                       + "`(rx_packets - rxp) / td` (Transport.py:652)")
        XCTAssertEqual(t.txPPS, 0)
    }

    func testPacketsPerSecondMeasuresTheIntervalNotTheLifetime() {
        let t = Transport()
        let iface = RecordingInterface(name: "Agg PPS 2")
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }
        t.startTime = 8_000

        for i in 0 ..< 100 { t.handleIncoming(packet: Self.plainPacket(byte: UInt8(i)), from: iface) }
        t.sampleInterfaceSpeeds(now: 8_010)
        XCTAssertEqual(t.rxPPS, 10)

        for i in 100 ..< 105 { t.handleIncoming(packet: Self.plainPacket(byte: UInt8(i)), from: iface) }
        t.sampleInterfaceSpeeds(now: 8_015)

        XCTAssertEqual(t.rxPPS, 1,
                       """
                       Python snapshots `rxp = Transport.rx_packets` at the end of each \
                       pass, so the next reading covers only the new interval \
                       (Transport.py:654). A rate divided into the lifetime count would \
                       read 7 here and would never fall back to idle.
                       """)
    }

    func testPacketsPerSecondIsZeroBeforeTransportStarts() {
        let t = Transport()
        let iface = RecordingInterface(name: "Agg PPS 3")
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }

        t.handleIncoming(packet: Self.plainPacket(), from: iface)
        t.sampleInterfaceSpeeds(now: 9_000)

        XCTAssertEqual(t.rxPPS, 0,
                       "`if not Transport.start_time: rpps = 0` (Transport.py:647)—with no "
                       + "start time there is no interval to divide by")
    }

    func testPacketsPerSecondRoundsTheWayPythonDoes() {
        let t = Transport()
        let iface = RecordingInterface(name: "Agg PPS 4")
        t.register(interface: iface)
        defer { t.deregister(interface: iface) }
        t.startTime = 10_000

        // 5 packets over 2 s = 2.5 pps. Python's `int(round(2.5))` is 2: round-half-to-even.
        for i in 0 ..< 5 { t.handleIncoming(packet: Self.plainPacket(byte: UInt8(i)), from: iface) }
        t.sampleInterfaceSpeeds(now: 10_002)

        XCTAssertEqual(t.rxPPS, 2,
                       """
                       `int(round(rpps))` (Transport.py:658) uses Python 3's banker's \
                       rounding. Swift's `rounded()` rounds half away from zero and would \
                       report 3—a one-packet disagreement that shows up in `rnstatus -p` \
                       side by side with a Python peer.
                       """)
    }

    // MARK: - Fixtures

    private static func singlePacket(byte: UInt8 = 0x01) -> Packet {
        Packet(destinationType: .single,
               packetType: .data,
               destinationHash: Data(repeating: 0x34, count: Constants.truncatedHashLength),
               data: Data([byte]))
    }

    private static func plainPacket(byte: UInt8 = 0x01) -> Packet {
        Packet(destinationType: .plain,
               packetType: .data,
               destinationHash: Data(repeating: 0x33, count: Constants.truncatedHashLength),
               data: Data([byte]))
    }

    private final class RecordingInterface: Interface {
        var name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    // MARK: - The outbound seam

    /// `Transport.swift` may hand a frame to an interface in exactly one place.
    ///
    /// This is a structural check, deliberately. `txPackets` is only as accurate as the
    /// number of send sites that remember to increment it, and Python avoids that problem by
    /// funnelling everything through `Transport.transmit` (`Transport.py:1325-1330`). A
    /// behavioural test can only cover the paths someone thought to write a fixture for, so
    /// it can never notice the nineteenth site that calls `interface.send` directly—which is
    /// how eighteen sites came to exist without a counter in the first place.
    func testEverySendGoesThroughTheTransmitSeam() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ReticulumSwiftTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("Sources/ReticulumSwift/Transport/Transport.swift")

        let lines = try String(contentsOf: source, encoding: .utf8).split(separator: "\n",
                                                                         omittingEmptySubsequences: false)

        // Strip comments before looking, so prose mentioning `.send()` doesn't register.
        let calls = lines.enumerated().compactMap { index, line -> String? in
            let code = line.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0]
            guard code.contains(".send(") else { return nil }
            return "\(index + 1): \(line.trimmingCharacters(in: .whitespaces))"
        }

        XCTAssertEqual(calls.count, 1, """
                       Transport.swift should contain exactly one `.send(` call—the one inside \
                       `transmit(_:on:)` that increments `txPackets`. Found:
                       \(calls.joined(separator: "\n"))
                       Route new outbound paths through `transmit(_:on:)`. If a call here is on \
                       something other than an interface, widen this check rather than deleting it.
                       """)
        XCTAssertTrue(calls.first?.contains("try interface.send(packet)") ?? false,
                      "the surviving call should be the one in the seam, but it was \(calls.first ?? "absent")")
    }
}
