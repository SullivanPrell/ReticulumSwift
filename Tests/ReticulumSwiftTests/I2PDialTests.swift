import XCTest
@testable import ReticulumSwift

// MARK: - Scripted SAM socket (no real i2pd / TCP needed)
//
// Follows the RNodeTransport pattern: production code talks to the SAM bridge
// through the SAMSocket protocol; tests inject scripted sockets that record
// every write and play back canned SAM replies.

final class MockSAMSocket: SAMSocket {
    private let lock = NSLock()

    /// Replies returned (in order) by `readLine`. Lines are without trailing newline.
    var scriptedReplies: [String]
    /// Every chunk passed to `write`, in order.
    private(set) var written: [Data] = []
    /// True once `startStreaming` was called (socket switched to data phase).
    private(set) var streaming = false
    /// True once production code called `close()`.
    private(set) var closedLocally = false
    var connectShouldFail = false

    private var streamHandler: ((Data) -> Void)?
    private var closeHandler: (() -> Void)?

    init(scriptedReplies: [String] = []) {
        self.scriptedReplies = scriptedReplies
    }

    // MARK: SAMSocket

    func connect(timeout: TimeInterval) throws {
        if connectShouldFail { throw SAMSocketError.connectFailed("mock refused") }
    }

    func write(_ data: Data) {
        lock.lock(); written.append(data); lock.unlock()
    }

    func readLine(timeout: TimeInterval) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard !scriptedReplies.isEmpty else { throw SAMSocketError.timeout }
        return scriptedReplies.removeFirst()
    }

    func startStreaming(_ handler: @escaping (Data) -> Void,
                        onClose: @escaping () -> Void) {
        lock.lock()
        streaming = true
        streamHandler = handler
        closeHandler = onClose
        lock.unlock()
    }

    func close() {
        lock.lock(); closedLocally = true; lock.unlock()
    }

    // MARK: Test helpers

    /// All written bytes decoded as UTF-8 (handshake lines).
    var writtenText: String {
        lock.lock(); defer { lock.unlock() }
        return written.compactMap { String(data: $0, encoding: .utf8) }.joined()
    }

    /// Raw writes made after the socket entered streaming mode are still in
    /// `written`; this returns them all concatenated for frame assertions.
    var writtenBytes: Data {
        lock.lock(); defer { lock.unlock() }
        return written.reduce(Data(), +)
    }

    /// Simulate inbound bytes arriving from the remote peer.
    func pushInbound(_ data: Data) {
        lock.lock(); let h = streamHandler; lock.unlock()
        h?(data)
    }

    /// Simulate the remote end (or i2pd) dropping the stream.
    func simulateRemoteClose() {
        lock.lock(); let h = closeHandler; lock.unlock()
        h?()
    }
}

/// Hands out pre-scripted sockets in creation order.
final class MockSAMSocketFactory {
    private let lock = NSLock()
    private var queue: [MockSAMSocket]
    private(set) var created: [MockSAMSocket] = []

    init(_ sockets: [MockSAMSocket]) { self.queue = sockets }

    func append(_ sockets: [MockSAMSocket]) {
        lock.lock(); queue.append(contentsOf: sockets); lock.unlock()
    }

    func make() -> SAMSocket {
        lock.lock(); defer { lock.unlock() }
        let s = queue.isEmpty ? MockSAMSocket() : queue.removeFirst()
        created.append(s)
        return s
    }

    var createdCount: Int {
        lock.lock(); defer { lock.unlock() }
        return created.count
    }
}

// MARK: - Canned reply builders

private let fakeB64Dest = "ZmFrZWRlc3RpbmF0aW9uYmFzZTY0ZGF0YQ~~"
private let helloOK = "HELLO REPLY RESULT=OK VERSION=3.1"

private func lookupSocket(value: String = fakeB64Dest) -> MockSAMSocket {
    MockSAMSocket(scriptedReplies: [
        helloOK,
        "NAMING REPLY RESULT=OK NAME=test VALUE=\(value)",
    ])
}

private func sessionSocket(result: String = "OK") -> MockSAMSocket {
    MockSAMSocket(scriptedReplies: [
        helloOK,
        "SESSION STATUS RESULT=\(result) DESTINATION=cHJpdmtleQ~~",
    ])
}

private func streamSocket(result: String = "OK") -> MockSAMSocket {
    MockSAMSocket(scriptedReplies: [
        helloOK,
        "STREAM STATUS RESULT=\(result)",
    ])
}

/// A peer wired to a scripted factory with fast test timings.
private func makePeer(target: String,
                      factory: MockSAMSocketFactory,
                      retryInterval: TimeInterval = 10) -> I2PInterfacePeer {
    let peer = I2PInterfacePeer(name: "test to \(target)",
                                targetI2PDestination: target,
                                parentInterface: nil)
    peer.socketFactory = { factory.make() }
    peer.retryInterval = retryInterval
    peer.handshakeTimeout = 1
    return peer
}

// MARK: - SAMClient additions (SILENT fix + NAMING LOOKUP)

final class SAMClientDialLineTests: XCTestCase {

    func testStreamConnectLineUsesSILENTParameter() {
        // SAM 3.1 spec (and i2plib) use SILENT=, not SILENCE=.
        let line = SAMClient.streamConnectLine(sessionID: "s1", destination: "dest")
        XCTAssertTrue(line.contains("SILENT=false"),
                      "STREAM CONNECT must carry SILENT=false (got: \(line))")
        XCTAssertFalse(line.contains("SILENCE"),
                       "SILENCE is not a SAM 3.1 parameter")
    }

    func testStreamAcceptLineUsesSILENTParameter() {
        let line = SAMClient.streamAcceptLine(sessionID: "s1")
        XCTAssertTrue(line.contains("SILENT=false"),
                      "STREAM ACCEPT must carry SILENT=false (got: \(line))")
        XCTAssertFalse(line.contains("SILENCE"))
    }

    func testNamingLookupLine() {
        let line = SAMClient.namingLookupLine(name: "abc.b32.i2p")
        XCTAssertEqual(line, "NAMING LOOKUP NAME=abc.b32.i2p\n",
                       "i2plib: NAMING LOOKUP NAME={}\\n")
    }

    func testParseNamingReplyOK() {
        let reply = "NAMING REPLY RESULT=OK NAME=abc.b32.i2p VALUE=ZmFrZQ~~\n"
        let result = SAMClient.parseNamingReply(reply)
        XCTAssertEqual(result, .ok("ZmFrZQ~~"))
    }

    func testParseNamingReplyFailure() {
        let reply = "NAMING REPLY RESULT=KEY_NOT_FOUND NAME=abc.b32.i2p\n"
        if case .failure(let reason) = SAMClient.parseNamingReply(reply) {
            XCTAssertTrue(reason.contains("KEY_NOT_FOUND"))
        } else {
            XCTFail("Expected failure")
        }
    }

    func testRandomSessionIDsAreUnique() {
        let a = SAMClient.randomSessionID()
        let b = SAMClient.randomSessionID()
        XCTAssertNotEqual(a, b)
        XCTAssertFalse(a.contains(" "), "Session IDs must not contain spaces")
    }
}

// MARK: - Outbound dial handshake

final class I2PPeerDialTests: XCTestCase {

    func testDialWithB32PerformsLookupSessionAndStreamConnect() {
        let factory = MockSAMSocketFactory([lookupSocket(), sessionSocket(), streamSocket()])
        let peer = makePeer(target: "abcd.b32.i2p", factory: factory)

        let online = expectation(description: "peer online")
        peer.onConnected = { _ in online.fulfill() }
        try? peer.start()
        wait(for: [online], timeout: 2)

        XCTAssertTrue(peer.isOnline)
        XCTAssertEqual(factory.createdCount, 3,
                       "b32 dial = lookup socket + session socket + stream socket")

        let lookup  = factory.created[0]
        let session = factory.created[1]
        let stream  = factory.created[2]

        XCTAssertTrue(lookup.writtenText.contains("HELLO VERSION MIN=3.1 MAX=3.1"))
        XCTAssertTrue(lookup.writtenText.contains("NAMING LOOKUP NAME=abcd.b32.i2p"))
        XCTAssertTrue(lookup.closedLocally, "Lookup socket is one-shot")

        XCTAssertTrue(session.writtenText.contains("SESSION CREATE STYLE=STREAM"))
        XCTAssertTrue(session.writtenText.contains("DESTINATION=TRANSIENT"))
        XCTAssertFalse(session.closedLocally,
                       "Session control socket must stay open (closing destroys the session)")

        XCTAssertTrue(stream.writtenText.contains("STREAM CONNECT"))
        XCTAssertTrue(stream.writtenText.contains("DESTINATION=\(fakeB64Dest)"),
                      "STREAM CONNECT must use the base64 dest from NAMING LOOKUP")
        XCTAssertTrue(stream.writtenText.contains("SILENT=false"))
        XCTAssertTrue(stream.streaming, "Stream socket must enter data phase after OK")

        // Both handshake sockets used the same session ID.
        let sessionID = SAMClient.extractValue(for: "ID", in: session.writtenText)
        XCTAssertNotNil(sessionID)
        XCTAssertEqual(SAMClient.extractValue(for: "ID", in: stream.writtenText), sessionID)

        XCTAssertTrue(peer.wantsTunnel,
                      "Python wait_job sets wants_tunnel before connecting")
        peer.stop()
    }

    func testDialWithFullBase64DestinationSkipsNamingLookup() {
        let factory = MockSAMSocketFactory([sessionSocket(), streamSocket()])
        let peer = makePeer(target: fakeB64Dest, factory: factory)

        let online = expectation(description: "peer online")
        peer.onConnected = { _ in online.fulfill() }
        try? peer.start()
        wait(for: [online], timeout: 2)

        XCTAssertEqual(factory.createdCount, 2,
                       "Full base64 destination needs no NAMING LOOKUP")
        XCTAssertTrue(factory.created[1].writtenText.contains("DESTINATION=\(fakeB64Dest)"))
        peer.stop()
    }

    func testPeerStartsOfflineAndStaysOfflineOnHandshakeFailure() {
        // Empty replies → readLine times out → dial fails.
        let factory = MockSAMSocketFactory([MockSAMSocket()])
        let peer = makePeer(target: "abcd.b32.i2p", factory: factory)
        XCTAssertFalse(peer.isOnline)

        var connected = false
        peer.onConnected = { _ in connected = true }
        try? peer.start()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(peer.isOnline)
        XCTAssertFalse(connected)
        peer.stop()
    }

    func testSessionCreateFailureRetriesAndSucceeds() {
        let factory = MockSAMSocketFactory([
            lookupSocket(), sessionSocket(result: "I2P_ERROR"),   // wave 1: fails
            lookupSocket(), sessionSocket(), streamSocket(),      // wave 2: succeeds
        ])
        let peer = makePeer(target: "abcd.b32.i2p", factory: factory, retryInterval: 0.05)

        let online = expectation(description: "online after retry")
        peer.onConnected = { _ in online.fulfill() }
        try? peer.start()
        wait(for: [online], timeout: 3)

        XCTAssertTrue(peer.isOnline)
        XCTAssertEqual(factory.createdCount, 5)
        XCTAssertTrue(factory.created[1].closedLocally,
                      "Failed session socket must be cleaned up")
        peer.stop()
    }
}

// MARK: - Data phase: framing in/out

final class I2PPeerDataPhaseTests: XCTestCase {

    private func onlinePeer(factory: MockSAMSocketFactory) -> I2PInterfacePeer {
        let peer = makePeer(target: fakeB64Dest, factory: factory)
        let online = expectation(description: "online")
        peer.onConnected = { _ in online.fulfill() }
        try? peer.start()
        wait(for: [online], timeout: 2)
        return peer
    }

    func testOutgoingDataIsHDLCFramedOntoStream() {
        let stream = streamSocket()
        let factory = MockSAMSocketFactory([sessionSocket(), stream])
        let peer = onlinePeer(factory: factory)

        let payload = Data([0x01, 0x7E, 0x02])   // contains a FLAG byte
        peer.processOutgoing(payload)

        let framed = HDLC.frame(payload)
        XCTAssertTrue(stream.writtenBytes.suffix(framed.count) == framed,
                      "Outgoing payload must be HDLC-framed onto the stream socket")
        XCTAssertEqual(peer.txBytes, framed.count,
                       "Python I2PInterfacePeer counts framed bytes: txb += len(framed)")
        peer.stop()
    }

    func testSendPacketWritesFramedPackedBytes() throws {
        let stream = streamSocket()
        let factory = MockSAMSocketFactory([sessionSocket(), stream])
        let peer = onlinePeer(factory: factory)

        let packet = Packet(destinationType: .single, packetType: .data,
                            destinationHash: Data(repeating: 0xAB, count: 16),
                            data: Data("hello i2p".utf8))
        try peer.send(packet)

        let framed = HDLC.frame(try packet.pack())
        XCTAssertTrue(stream.writtenBytes.suffix(framed.count) == framed)
        peer.stop()
    }

    func testInboundStreamBytesAreUnframedAndDelivered() {
        let stream = streamSocket()
        let factory = MockSAMSocketFactory([sessionSocket(), stream])
        let peer = onlinePeer(factory: factory)

        var receivedFrames: [Data] = []
        peer.rawInboundHandler = { frame, _ in receivedFrames.append(frame) }

        let payload = Data([0xAA, 0xBB, 0x7E, 0xCC])
        stream.pushInbound(HDLC.frame(payload))

        XCTAssertEqual(receivedFrames, [payload])
        XCTAssertEqual(peer.rxBytes, payload.count,
                       "Python: rxb += len(unframed payload)")
        peer.stop()
    }

    func testInboundKeepaliveFlagsAreIgnored() {
        let stream = streamSocket()
        let factory = MockSAMSocketFactory([sessionSocket(), stream])
        let peer = onlinePeer(factory: factory)

        var receivedFrames: [Data] = []
        peer.rawInboundHandler = { frame, _ in receivedFrames.append(frame) }

        stream.pushInbound(Data([HDLC.flag, HDLC.flag]))   // bare keepalive
        XCTAssertTrue(receivedFrames.isEmpty, "Empty frames must be dropped")
        peer.stop()
    }
}

// MARK: - Reconnect & watchdog

final class I2PPeerReconnectTests: XCTestCase {

    func testRemoteCloseTriggersOfflineAndReconnect() {
        let stream1 = streamSocket()
        let factory = MockSAMSocketFactory([sessionSocket(), stream1])
        let peer = makePeer(target: fakeB64Dest, factory: factory, retryInterval: 0.05)

        let online1 = expectation(description: "online first time")
        peer.onConnected = { _ in online1.fulfill() }
        try? peer.start()
        wait(for: [online1], timeout: 2)

        // Queue the second wave, then drop the stream.
        factory.append([sessionSocket(), streamSocket()])
        let offline = expectation(description: "went offline")
        offline.assertForOverFulfill = false   // peer.stop() below also disconnects
        peer.onDisconnected = { _ in offline.fulfill() }
        let online2 = expectation(description: "back online")
        peer.onConnected = { _ in online2.fulfill() }

        stream1.simulateRemoteClose()
        wait(for: [offline, online2], timeout: 3)

        XCTAssertTrue(peer.isOnline)
        XCTAssertEqual(factory.createdCount, 4, "Reconnect dials a fresh session + stream")
        peer.stop()
    }

    func testStopDetachesAndStopsReconnecting() {
        let factory = MockSAMSocketFactory([sessionSocket(), streamSocket()])
        let peer = makePeer(target: fakeB64Dest, factory: factory, retryInterval: 0.05)

        let online = expectation(description: "online")
        peer.onConnected = { _ in online.fulfill() }
        try? peer.start()
        wait(for: [online], timeout: 2)

        peer.stop()
        XCTAssertFalse(peer.isOnline)
        let countAfterStop = factory.createdCount
        Thread.sleep(forTimeInterval: 0.25)
        XCTAssertEqual(factory.createdCount, countAfterStop,
                       "A stopped (detached) peer must not redial")
    }

    func testKeepaliveFlagsSentWhenIdle() {
        let stream = streamSocket()
        let factory = MockSAMSocketFactory([sessionSocket(), stream])
        let peer = makePeer(target: fakeB64Dest, factory: factory)
        peer.probeAfterInterval = 0.05
        peer.watchdogTick = 0.02

        let online = expectation(description: "online")
        peer.onConnected = { _ in online.fulfill() }
        try? peer.start()
        wait(for: [online], timeout: 2)

        // Idle: watchdog must emit the 2-byte HDLC keepalive (Python: FLAG FLAG).
        let deadline = Date().addingTimeInterval(2)
        var sawKeepalive = false
        let keepalive = Data([HDLC.flag, HDLC.flag])
        while Date() < deadline {
            if stream.writtenBytes.range(of: keepalive) != nil { sawKeepalive = true; break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(sawKeepalive, "Idle peer must send HDLC FLAG FLAG keepalives")
        peer.stop()
    }

    func testReadTimeoutForcesReconnect() {
        let factory = MockSAMSocketFactory([sessionSocket(), streamSocket()])
        let peer = makePeer(target: fakeB64Dest, factory: factory, retryInterval: 10)
        peer.readTimeoutInterval = 0.15
        peer.watchdogTick = 0.05

        let online = expectation(description: "online")
        peer.onConnected = { _ in online.fulfill() }
        try? peer.start()
        wait(for: [online], timeout: 2)

        let offline = expectation(description: "watchdog killed stale socket")
        peer.onDisconnected = { _ in offline.fulfill() }
        wait(for: [offline], timeout: 3)
        XCTAssertFalse(peer.isOnline)
        peer.stop()
    }
}

// MARK: - I2PInterface spawning + Transport integration

final class I2PInterfacePeerSpawnTests: XCTestCase {

    private func makeInterface(peers: [String],
                               factory: MockSAMSocketFactory,
                               daemon: MockI2PDaemon = MockI2PDaemon()) -> I2PInterface {
        let iface = I2PInterface(name: "I2P", daemon: daemon,
                                 dataDirectory: URL(fileURLWithPath: "/tmp/i2p-test"),
                                 connectable: false,
                                 peers: peers)
        iface.samSocketFactory = { factory.make() }
        return iface
    }

    func testInterfaceIsNotRoutingEndpoint() {
        let iface = makeInterface(peers: [], factory: MockSAMSocketFactory([]))
        XCTAssertFalse(iface.isRoutingEndpoint,
                       "Python parent I2PInterface never transmits (process_outgoing: pass)")
    }

    func testStartSpawnsOnePeerPerConfiguredDestination() {
        let factory = MockSAMSocketFactory([
            sessionSocket(), streamSocket(),
            sessionSocket(), streamSocket(),
        ])
        let daemon = MockI2PDaemon()
        let iface = makeInterface(peers: [fakeB64Dest, fakeB64Dest + "2"],
                                  factory: factory, daemon: daemon)

        let bothOnline = expectation(description: "both peers online")
        bothOnline.expectedFulfillmentCount = 2
        iface.onPeerConnected = { _ in bothOnline.fulfill() }

        try? iface.start()
        wait(for: [bothOnline], timeout: 3)

        XCTAssertEqual(daemon.startCallCount, 1)
        XCTAssertEqual(iface.peerInterfaces.count, 2)
        XCTAssertEqual(iface.peerInterfaces[0].name, "I2P to \(fakeB64Dest)",
                       "Python: interface_name = name + \" to \" + peer_addr")
        XCTAssertTrue(iface.peerInterfaces.allSatisfy { $0.isOnline })
        iface.stop()
    }

    func testStopStopsDaemonAndPeers() {
        let factory = MockSAMSocketFactory([sessionSocket(), streamSocket()])
        let daemon = MockI2PDaemon()
        let iface = makeInterface(peers: [fakeB64Dest], factory: factory, daemon: daemon)

        let online = expectation(description: "online")
        iface.onPeerConnected = { _ in online.fulfill() }
        try? iface.start()
        wait(for: [online], timeout: 2)

        let spawnedPeer = iface.peerInterfaces[0]
        iface.stop()
        XCTAssertEqual(daemon.stopCallCount, 1)
        XCTAssertFalse(spawnedPeer.isOnline)
        XCTAssertTrue(iface.peerInterfaces.isEmpty,
                      "stop() clears spawned peers; start() respawns from config")
    }

    func testTransportRegistersAndDeregistersDialedPeers() {
        let stream = streamSocket()
        let factory = MockSAMSocketFactory([sessionSocket(), stream])
        let iface = makeInterface(peers: [fakeB64Dest], factory: factory)

        let transport = Transport()
        transport.register(interface: iface)

        let online = expectation(description: "peer online")
        let existing = iface.onPeerConnected   // Transport's wiring
        iface.onPeerConnected = { peer in existing?(peer); online.fulfill() }

        try? iface.start()
        wait(for: [online], timeout: 2)

        let peer = iface.peerInterfaces[0]
        XCTAssertTrue(transport.interfaces.contains { $0 === peer },
                      "Dialed peer must be registered with Transport as routing endpoint")

        let offline = expectation(description: "peer offline")
        let existingOff = iface.onPeerDisconnected
        iface.onPeerDisconnected = { p in existingOff?(p); offline.fulfill() }
        stream.simulateRemoteClose()
        wait(for: [offline], timeout: 2)

        XCTAssertFalse(transport.interfaces.contains { $0 === peer },
                       "Dropped peer must be deregistered from Transport")
        iface.stop()
    }
}
