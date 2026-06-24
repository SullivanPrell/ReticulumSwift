import XCTest
@testable import ReticulumSwift

// MARK: - Mock BLE mesh transport

/// In-memory stand-in for a CoreBluetooth-backed `BLEMeshTransport`.
/// Lets tests simulate peer connect/disconnect and byte arrival without
/// any live radio hardware — exactly the role `MockRNodeTransport` plays
/// for `RNodeInterfaceTests`.
private final class MockBLEMeshTransport: BLEMeshTransport {
    var peerConnected: ((BLEMeshPeerID) -> Void)?
    var peerDisconnected: ((BLEMeshPeerID) -> Void)?
    var peerDataHandler: ((BLEMeshPeerID, Data) -> Void)?

    private(set) var connectedPeers: [BLEMeshPeerID] = []
    private(set) var startCalled = false
    private(set) var stopCalled = false

    /// Records every `send(_:to:)` call as (peer, bytes) for assertions.
    private(set) var sent: [(peer: BLEMeshPeerID, data: Data)] = []

    var sendError: Error?

    func start() throws { startCalled = true }
    func stop() { stopCalled = true; connectedPeers.removeAll() }

    func send(_ data: Data, to peer: BLEMeshPeerID) throws {
        if let sendError { throw sendError }
        sent.append((peer, data))
    }

    // MARK: - Test helpers (simulate radio events)

    func simulateConnect(_ peer: BLEMeshPeerID) {
        connectedPeers.append(peer)
        peerConnected?(peer)
    }

    func simulateDisconnect(_ peer: BLEMeshPeerID) {
        connectedPeers.removeAll { $0 == peer }
        peerDisconnected?(peer)
    }

    /// Simulates bytes arriving from `peer`, optionally split into chunks
    /// to model BLE MTU fragmentation.
    func simulateReceive(from peer: BLEMeshPeerID, chunks: [Data]) {
        for chunk in chunks {
            peerDataHandler?(peer, chunk)
        }
    }
}

private enum MockTransportError: Error { case boom }

// MARK: - BLEMeshInterfaceTests

final class BLEMeshInterfaceTests: XCTestCase {

    private func makePacket(payload: String = "hello mesh") -> Packet {
        Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xCD, count: Constants.truncatedHashLength),
            data: Data(payload.utf8)
        )
    }

    // MARK: - Initial state

    func testInitialState() {
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)

        XCTAssertEqual(iface.name, "ble0")
        XCTAssertFalse(iface.isOnline)
        XCTAssertEqual(iface.peerCount, 0)
        XCTAssertEqual(iface.connectedPeerIDs, [])
        XCTAssertEqual(iface.rxBytes, 0)
        XCTAssertEqual(iface.txBytes, 0)
        XCTAssertEqual(iface.rxPackets, 0)
        XCTAssertEqual(iface.txPackets, 0)
    }

    func testDisplayNameMatchesTypeQualifiedConvention() {
        let iface = BLEMeshInterface(name: "phone-mesh", transport: MockBLEMeshTransport())
        XCTAssertEqual(iface.displayName, "BLEMeshInterface[phone-mesh]")
        // hash / getHash() must agree, be a well-formed SHA-256 digest, and —
        // mirroring Python's `get_hash()` = `full_hash(str(self).encode())` —
        // be derived from the type-qualified `displayName`, not the bare `name`.
        XCTAssertEqual(iface.hash, iface.getHash())
        XCTAssertEqual(iface.hash.count, 32)
        XCTAssertEqual(iface.hash, Hashes.fullHash(Data(iface.displayName.utf8)))
    }

    func testDeclaresFixedHardwareMtuAtPacketCeiling() {
        let iface = BLEMeshInterface(name: "ble0", transport: MockBLEMeshTransport())
        XCTAssertEqual(iface.hwMtu, Constants.mtu)
        XCTAssertTrue(iface.fixedMtu)
    }

    func testDefaultBitrateGuess() {
        let iface = BLEMeshInterface(name: "ble0", transport: MockBLEMeshTransport())
        XCTAssertEqual(iface.bitrate, BLEMeshInterface.bitrateGuess)

        let custom = BLEMeshInterface(name: "ble1", transport: MockBLEMeshTransport(), bitrate: 250_000)
        XCTAssertEqual(custom.bitrate, 250_000)
    }

    // MARK: - Lifecycle

    func testStartWiresTransportAndGoesOnline() throws {
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)

        XCTAssertNil(transport.peerConnected)
        try iface.start()

        XCTAssertTrue(transport.startCalled)
        XCTAssertTrue(iface.isOnline)
        // The interface must have installed its callbacks before starting
        // the radio, or early peer events would be dropped.
        XCTAssertNotNil(transport.peerConnected)
        XCTAssertNotNil(transport.peerDisconnected)
        XCTAssertNotNil(transport.peerDataHandler)
    }

    func testStopTearsDownTransportAndClearsPeers() throws {
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()
        transport.simulateConnect("peer-a")
        XCTAssertEqual(iface.peerCount, 1)

        iface.stop()

        XCTAssertFalse(iface.isOnline)
        XCTAssertTrue(transport.stopCalled)
        XCTAssertEqual(iface.peerCount, 0)
    }

    func testSendIsNoOpWhileOffline() throws {
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        // Never started — interface is offline.
        try iface.send(makePacket())
        XCTAssertEqual(transport.sent.count, 0)
        XCTAssertEqual(iface.txBytes, 0)
        XCTAssertEqual(iface.txPackets, 0)
    }

    // MARK: - Peer tracking

    func testPeerConnectAndDisconnectUpdatesTable() throws {
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()

        transport.simulateConnect("peer-a")
        transport.simulateConnect("peer-b")
        XCTAssertEqual(iface.peerCount, 2)
        XCTAssertEqual(Set(iface.connectedPeerIDs), Set(["peer-a", "peer-b"]))

        transport.simulateDisconnect("peer-a")
        XCTAssertEqual(iface.peerCount, 1)
        XCTAssertEqual(iface.connectedPeerIDs, ["peer-b"])
    }

    // MARK: - Outbound: HDLC framing + fan-out broadcast

    func testSendFramesWithHdlcAndBroadcastsToAllPeers() throws {
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()
        transport.simulateConnect("peer-a")
        transport.simulateConnect("peer-b")

        let packet = makePacket()
        try iface.send(packet)

        // Broadcast: every connected peer receives an identical framed copy.
        XCTAssertEqual(transport.sent.count, 2)
        let recipients = Set(transport.sent.map(\.peer))
        XCTAssertEqual(recipients, Set(["peer-a", "peer-b"]))

        let raw = try packet.pack()
        let expectedFramed = HDLC.frame(iface.wrapIfac(raw))
        for entry in transport.sent {
            XCTAssertEqual(entry.data, expectedFramed)
        }

        // Stats: Python convention counts unframed payload bytes, once
        // per send (not once per recipient).
        XCTAssertEqual(iface.txBytes, raw.count)
        XCTAssertEqual(iface.txPackets, 1)
    }

    func testSendToZeroPeersStillCountsAsTransmitted() throws {
        // Mirrors AutoInterface: an interface with no peers yet still
        // "sends" (and counts) — it just has nobody to broadcast to.
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()

        let packet = makePacket()
        try iface.send(packet)

        XCTAssertEqual(transport.sent.count, 0)
        XCTAssertEqual(iface.txPackets, 1)
        XCTAssertEqual(iface.txBytes, try packet.pack().count)
    }

    func testSendToleratesPerPeerTransportFailures() throws {
        let transport = MockBLEMeshTransport()
        transport.sendError = MockTransportError.boom
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()
        transport.simulateConnect("peer-a")

        // Must not throw — a single peer's radio failure shouldn't abort
        // the whole broadcast or crash the caller (mirrors `try?` patterns
        // used for per-recipient sends elsewhere, e.g. AutoInterface).
        XCTAssertNoThrow(try iface.send(makePacket()))
    }

    // MARK: - Inbound: per-peer reassembly

    func testReceiveCompleteFrameDeliversPacket() throws {
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()
        transport.simulateConnect("peer-a")

        let packet = makePacket(payload: "single-shot")
        let framed = HDLC.frame(iface.wrapIfac(try packet.pack()))

        var received: [(Packet, String)] = []
        iface.inboundHandler = { pkt, ifc in received.append((pkt, ifc.name)) }

        transport.simulateReceive(from: "peer-a", chunks: [framed])

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0.data, packet.data)
        XCTAssertEqual(received.first?.1, "ble0")
        XCTAssertEqual(iface.rxPackets, 1)
        XCTAssertEqual(iface.rxBytes, try packet.pack().count)
    }

    func testReceiveReassemblesFragmentedFrame() throws {
        // BLE GATT payloads are MTU-bound — a Reticulum packet routinely
        // arrives split across many notifications. The interface must
        // reassemble before attempting to unpack.
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()
        transport.simulateConnect("peer-a")

        let packet = makePacket(payload: "fragmented across many tiny BLE chunks")
        let framed = HDLC.frame(iface.wrapIfac(try packet.pack()))

        // Chop into 5-byte chunks to simulate a small negotiated link MTU.
        var chunks: [Data] = []
        var idx = framed.startIndex
        while idx < framed.endIndex {
            let end = framed.index(idx, offsetBy: 5, limitedBy: framed.endIndex) ?? framed.endIndex
            chunks.append(framed[idx..<end])
            idx = end
        }
        XCTAssertGreaterThan(chunks.count, 1, "test setup sanity: must actually fragment")

        var received: [Packet] = []
        iface.inboundHandler = { pkt, _ in received.append(pkt) }
        transport.simulateReceive(from: "peer-a", chunks: chunks)

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.data, packet.data)
    }

    func testReceiveKeepsPerPeerDecodersIndependent() throws {
        // A partial frame from one peer must never be mixed with another
        // peer's bytes — each link gets its own reassembly state.
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()
        transport.simulateConnect("peer-a")
        transport.simulateConnect("peer-b")

        let packetA = makePacket(payload: "from peer A")
        let packetB = makePacket(payload: "from peer B, a longer payload than A's")
        let framedA = HDLC.frame(iface.wrapIfac(try packetA.pack()))
        let framedB = HDLC.frame(iface.wrapIfac(try packetB.pack()))

        // Interleave: half of A, all of B, then the rest of A.
        let splitA = framedA.count / 2
        let aHead = framedA.prefix(splitA)
        let aTail = framedA.suffix(from: splitA)

        var received: [(peer: String, payload: Data)] = []
        iface.inboundHandler = { pkt, _ in received.append(("?", pkt.data)) }

        transport.simulateReceive(from: "peer-a", chunks: [Data(aHead)])
        transport.simulateReceive(from: "peer-b", chunks: [framedB])
        transport.simulateReceive(from: "peer-a", chunks: [Data(aTail)])

        XCTAssertEqual(received.count, 2)
        let payloads = Set(received.map(\.payload))
        XCTAssertEqual(payloads, Set([packetA.data, packetB.data]))
    }

    func testReceiveTracksUnknownPeerWithoutDroppingData() throws {
        // Bytes can race the connect callback in a real radio stack — the
        // interface must not silently drop them.
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()
        // Note: no simulateConnect("peer-a") — data arrives "out of band".

        let packet = makePacket()
        let framed = HDLC.frame(iface.wrapIfac(try packet.pack()))

        var received: [Packet] = []
        iface.inboundHandler = { pkt, _ in received.append(pkt) }
        transport.simulateReceive(from: "peer-a", chunks: [framed])

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(iface.peerCount, 1, "peer should be tracked once we hear from it")
    }

    func testRawInboundHandlerReceivesFramesInsteadOfParsedPackets() throws {
        // Mirrors TCPClientInterface: when Transport needs to verify IFAC
        // itself, it installs rawInboundHandler and the interface must NOT
        // also invoke inboundHandler.
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()
        transport.simulateConnect("peer-a")

        let packet = makePacket()
        let raw = try packet.pack()
        let wrapped = iface.wrapIfac(raw)
        let framed = HDLC.frame(wrapped)

        var rawFrames: [Data] = []
        var parsedPackets: [Packet] = []
        iface.rawInboundHandler = { data, _ in rawFrames.append(data) }
        iface.inboundHandler = { pkt, _ in parsedPackets.append(pkt) }

        transport.simulateReceive(from: "peer-a", chunks: [framed])

        XCTAssertEqual(rawFrames, [wrapped])
        XCTAssertTrue(parsedPackets.isEmpty)
    }

    func testPeerDisconnectDuringActiveReassemblyDropsPartialState() throws {
        let transport = MockBLEMeshTransport()
        let iface = BLEMeshInterface(name: "ble0", transport: transport)
        try iface.start()
        transport.simulateConnect("peer-a")

        let packet = makePacket(payload: "will be interrupted mid-frame")
        let framed = HDLC.frame(iface.wrapIfac(try packet.pack()))
        let half = framed.prefix(framed.count / 2)

        transport.simulateReceive(from: "peer-a", chunks: [Data(half)])
        transport.simulateDisconnect("peer-a")
        XCTAssertEqual(iface.peerCount, 0)

        // Reconnect and send a fresh, complete frame — it must decode
        // cleanly, proving the old partial buffer didn't leak forward.
        transport.simulateConnect("peer-a")
        var received: [Packet] = []
        iface.inboundHandler = { pkt, _ in received.append(pkt) }

        let freshPacket = makePacket(payload: "fresh start")
        let freshFramed = HDLC.frame(iface.wrapIfac(try freshPacket.pack()))
        transport.simulateReceive(from: "peer-a", chunks: [freshFramed])

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.data, freshPacket.data)
    }
}
