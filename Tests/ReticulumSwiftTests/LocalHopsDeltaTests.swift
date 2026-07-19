import XCTest
@testable import ReticulumSwift

/// Tests for the `local_hops_delta` privacy feature — per-session hop-count
/// obfuscation for packets that originate locally (our own traffic and traffic
/// relayed for directly-connected local clients).
///
/// Mirrors Python `Transport.local_hops_delta` / `should_apply_delta` /
/// `mangle_hops` and the `instance_local_link` / `proof_for_local_client` /
/// `to_local_client` relay distinctions.
final class LocalHopsDeltaTests: XCTestCase {

    // Records the last packet handed to it, so we can inspect the mangled hops.
    final class CapturingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    // Stands in for the shared-instance SERVER side (e.g. PosixTCPServer): the
    // interface a directly-connected local client's traffic arrives on. This —
    // not LocalInterface (the client side) — is what Python treats as a
    // local-client interface (see TransportUtilityTests).
    final class ServingInterface: Interface, LocalClientServingInterface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var clientCount: Int = 1
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws {}
    }

    private func singleDataPacket(hops: UInt8 = 0) -> Packet {
        var p = Packet(destinationType: .single, packetType: .data,
                       destinationHash: Data(repeating: 0x5A, count: Constants.truncatedHashLength),
                       data: Data(repeating: 0x01, count: 16))
        p.hops = hops
        return p
    }

    // MARK: - Config + default

    func testConfigParsesLocalHopsDeltaEnabled() {
        let cfg = ReticulumConfig.parse("""
        [reticulum]
        local_hops_delta = Yes
        """)
        XCTAssertTrue(cfg.reticulum.localHopsDelta, "local_hops_delta = Yes must parse to true")
    }

    func testConfigLocalHopsDeltaDefaultsFalse() {
        let cfg = ReticulumConfig.parse("[reticulum]")
        XCTAssertFalse(cfg.reticulum.localHopsDelta, "local_hops_delta must default to false")
    }

    func testTransportLocalHopsDeltaDefaultsToZero() {
        XCTAssertEqual(Transport().localHopsDelta, 0, "Feature is disabled (delta 0) by default")
    }

    // MARK: - shouldApplyDelta

    func testShouldApplyDeltaFalseWhenDisabled() {
        let t = Transport()   // localHopsDelta == 0
        XCTAssertFalse(t.shouldApplyDelta(singleDataPacket(), interface: CapturingInterface(name: "net")))
    }

    func testShouldApplyDeltaTrueForOwnPacketOnRealInterface() {
        let t = Transport(); t.localHopsDelta = 3
        XCTAssertTrue(t.shouldApplyDelta(singleDataPacket(), interface: CapturingInterface(name: "net")),
                      "Own hops==0 SINGLE packet on a non-local interface must be obfuscated")
    }

    func testShouldApplyDeltaFalseWhenConnectedToSharedInstance() {
        let t = Transport(); t.localHopsDelta = 3; t.isConnectedToSharedInstance = true
        XCTAssertFalse(t.shouldApplyDelta(singleDataPacket(), interface: CapturingInterface(name: "net")),
                       "A client behind a shared instance must not obfuscate — the instance does it")
    }

    func testShouldApplyDeltaFalseWhenHopsNonZero() {
        let t = Transport(); t.localHopsDelta = 3
        XCTAssertFalse(t.shouldApplyDelta(singleDataPacket(hops: 1), interface: CapturingInterface(name: "net")),
                       "Only freshly-originated (hops==0) packets are obfuscated")
    }

    func testShouldApplyDeltaFalseForPlainDestination() {
        let t = Transport(); t.localHopsDelta = 3
        var p = singleDataPacket()
        p = Packet(destinationType: .plain, packetType: .data,
                   destinationHash: p.destinationHash, data: p.data)
        XCTAssertFalse(t.shouldApplyDelta(p, interface: CapturingInterface(name: "net")),
                       "PLAIN destinations are never obfuscated")
    }

    func testShouldApplyDeltaFalseOnLocalClientInterface() {
        let t = Transport(); t.localHopsDelta = 3
        let local = LocalInterface(name: "lo-delta")
        XCTAssertFalse(t.shouldApplyDelta(singleDataPacket(), interface: local),
                       "Traffic to a local client must keep real hops")
    }

    // MARK: - mangleHops

    func testMangleHopsSetsHopByte() {
        let t = Transport()
        let out = t.mangleHops(singleDataPacket(hops: 0), hops: 5)
        XCTAssertEqual(out.hops, 5)
    }

    func testMangleHopsTransportInsertPromotesToHeader2() {
        let t = Transport()
        let announce = Packet(headerType: .type1, destinationType: .single, packetType: .announce,
                              destinationHash: Data(repeating: 0x11, count: Constants.truncatedHashLength),
                              data: Data(count: 8))
        let out = t.mangleHops(announce, hops: 4, transportInsert: true)
        XCTAssertEqual(out.hops, 4)
        XCTAssertEqual(out.headerType, .type2, "transport_insert must promote to HEADER_2")
        XCTAssertEqual(out.transportType, .transport)
        XCTAssertEqual(out.transportID, t.transportInstanceID, "must carry this instance's transport id")
    }

    // MARK: - relayHops (instance_local_link / proof_for_local_client / to_local_client)

    func testRelayHopsIncrementsWhenDisabled() {
        let t = Transport()   // delta 0
        let local = LocalInterface(name: "lo-relay-off")
        XCTAssertEqual(t.relayHops(singleDataPacket(hops: 2), from: local, staysLocal: false), 3,
                       "With the feature off, relay always does hops+1")
    }

    func testRelayHopsObfuscatesLocalClientTrafficLeavingDomain() {
        let t = Transport(); t.localHopsDelta = 6
        let serving = ServingInterface(name: "serving-relay")
        XCTAssertEqual(t.relayHops(singleDataPacket(hops: 2), from: serving, staysLocal: false), 6,
                       "Local-client traffic leaving the local domain is obfuscated to the delta")
    }

    func testRelayHopsKeepsRealHopsWhenStaysLocal() {
        let t = Transport(); t.localHopsDelta = 6
        let serving = ServingInterface(name: "serving-relay-stay")
        XCTAssertEqual(t.relayHops(singleDataPacket(hops: 2), from: serving, staysLocal: true), 3,
                       "instance_local_link / proof_for_local_client / to_local_client keeps real hops")
    }

    func testRelayHopsIncrementsForNonLocalSource() {
        let t = Transport(); t.localHopsDelta = 6
        let net = CapturingInterface(name: "net-relay")
        XCTAssertEqual(t.relayHops(singleDataPacket(hops: 2), from: net, staysLocal: false), 3,
                       "Traffic not from a local client is never obfuscated")
    }

    // MARK: - End-to-end outbound obfuscation via send()

    func testOutboundSendObfuscatesOwnPacketHops() throws {
        let t = Transport(); t.localHopsDelta = 4
        let net = CapturingInterface(name: "net-out")
        t.register(interface: net)
        // No known path + not locally registered → broadcast on all interfaces.
        _ = try t.send(singleDataPacket(), generateReceipt: false)
        XCTAssertEqual(net.sent.count, 1)
        XCTAssertEqual(net.sent.first?.hops, 4,
                       "Our own hops==0 packet must leave with hops == localHopsDelta")
    }

    func testOutboundSendLeavesHopsUnchangedWhenDisabled() throws {
        let t = Transport()   // delta 0
        let net = CapturingInterface(name: "net-out-off")
        t.register(interface: net)
        _ = try t.send(singleDataPacket(), generateReceipt: false)
        XCTAssertEqual(net.sent.first?.hops, 0,
                       "With the feature off, hops are unchanged (default behavior)")
    }
}
