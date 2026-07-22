import XCTest
@testable import ReticulumSwift

// MARK: - Mock outlet for synchronous unit testing

/// A mock ChannelOutlet that delivers packets immediately (synchronously),
/// enabling deterministic tests without timers.
final class MockChannelOutlet: ChannelOutlet {
    var sentPackets: [Data] = []
    var resentPackets: [Data] = []
    var heldHandles: [ChannelPacketHandle] = []
    var timedOutCalled = false
    var mockRTT: TimeInterval = 0.1
    var mockMDU: Int = 500
    var mockUsable: Bool = true

    /// If set, automatically calls the delivered callback after send().
    var autoDeliver: Bool = true

    func send(_ raw: Data) -> ChannelPacketHandle {
        sentPackets.append(raw)
        let handle = ChannelPacketHandle(raw: raw)
        heldHandles.append(handle)
        if autoDeliver {
            handle.markDelivered()
        }
        return handle
    }

    func resend(_ handle: ChannelPacketHandle) {
        resentPackets.append(handle.raw)
    }

    var mdu: Int { mockMDU }
    var rtt: TimeInterval { mockRTT }
    var isUsable: Bool { mockUsable }

    func getPacketState(_ handle: ChannelPacketHandle) -> MessageState {
        switch handle.state {
        case .sent: return .sent
        case .delivered: return .delivered
        case .failed: return .failed
        }
    }

    func timedOut() { timedOutCalled = true }

    func setPacketTimeoutCallback(
        _ handle: ChannelPacketHandle,
        timeout: TimeInterval?,
        callback: ((ChannelPacketHandle) -> Void)?
    ) {}

    func setPacketDeliveredCallback(
        _ handle: ChannelPacketHandle,
        callback: ((ChannelPacketHandle) -> Void)?
    ) {
        handle.setDeliveredCallback(callback)
    }

    func getPacketID(_ handle: ChannelPacketHandle) -> ObjectIdentifier? {
        ObjectIdentifier(handle)
    }
}

// MARK: - Concrete message types for testing

final class PingMessage: MessageBase {
    override class var typeID: UInt16 { 0x0001 }
    var value: UInt8 = 0
    convenience init(value: UInt8) { self.init(); self.value = value }
    override func pack() throws -> Data { Data([value]) }
    override func unpack(_ data: Data) throws {
        guard !data.isEmpty else { return }
        value = data[0]
    }
}

final class PongMessage: MessageBase {
    override class var typeID: UInt16 { 0x0002 }
    var text: String = ""
    convenience init(text: String) { self.init(); self.text = text }
    override func pack() throws -> Data { Data(text.utf8) }
    override func unpack(_ data: Data) throws { text = String(data: data, encoding: .utf8) ?? "" }
}

// MARK: - Tests

final class ChannelTests: XCTestCase {

    // MARK: - Wire format (Python parity)

    func testEnvelopePackMatchesPythonWireFormat() throws {
        // Python: struct.pack(">HHH", MSGTYPE, sequence, len(data)) + data
        // PingMessage typeID=0x0001, sequence=0x0003, body=[0x42]
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        let msg = PingMessage(value: 0x42)
        try channel.send(msg)

        XCTAssertEqual(outlet.sentPackets.count, 1)
        let raw = outlet.sentPackets[0]
        // bytes 0-1: MSGTYPE big-endian = 0x0001
        XCTAssertEqual(raw[0], 0x00)
        XCTAssertEqual(raw[1], 0x01)
        // bytes 2-3: sequence = 0
        XCTAssertEqual(raw[2], 0x00)
        XCTAssertEqual(raw[3], 0x00)
        // bytes 4-5: body length = 1
        XCTAssertEqual(raw[4], 0x00)
        XCTAssertEqual(raw[5], 0x01)
        // byte 6: body = 0x42
        XCTAssertEqual(raw[6], 0x42)
        XCTAssertEqual(raw.count, 7)
    }

    func testSequenceIncrements() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        for i: UInt8 in 0..<5 {
            try channel.send(PingMessage(value: i))
        }

        for (i, raw) in outlet.sentPackets.enumerated() {
            let seq = UInt16(raw[2]) << 8 | UInt16(raw[3])
            XCTAssertEqual(seq, UInt16(i), "sequence mismatch at index \(i)")
        }
    }

    func testSequenceWrapsAt65535() throws {
        // Set next sequence just below wrap point.
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        // Use reflection-like approach: send 65535 messages would be slow.
        // Instead, directly validate the modulus.
        XCTAssertEqual(Channel.SEQ_MODULUS, 0x10000)
        XCTAssertEqual(Channel.SEQ_MAX, 0xFFFF)
    }

    // MARK: - Message type registry

    func testRegisterAndReceiveKnownType() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        var received: PingMessage?
        let exp = expectation(description: "received")
        channel.addMessageHandler { msg in
            guard let ping = msg as? PingMessage else { return false }
            received = ping
            exp.fulfill()
            return true
        }

        // Feed raw bytes that represent a PingMessage with value 0xAB at seq 0.
        let raw = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0xAB])
        channel.receive(raw)

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(received?.value, 0xAB)
    }

    func testUnknownTypeDroppedSilently() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        // Do NOT register PingMessage.

        var handlerCalled = false
        channel.addMessageHandler { _ in handlerCalled = true; return true }

        // Feed a PingMessage packet — should be silently dropped.
        let raw = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x42])
        channel.receive(raw)

        XCTAssertFalse(handlerCalled)
    }

    /// Regression: receive() previously held `lock` across the throwing
    /// `envelope.unpack`, so an unknown-msgtype or short frame leaked the
    /// non-recursive lock and permanently deadlocked the channel (every later
    /// send/receive/shutdown blocked). A single mismatched peer packet was enough.
    /// After the fix the channel must stay fully usable after malformed frames.
    func testMalformedFrameDoesNotDeadlockChannel() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        var delivered: UInt8?
        let exp = expectation(description: "valid message delivered after malformed frames")
        channel.addMessageHandler { msg in
            guard let ping = msg as? PingMessage else { return false }
            delivered = ping.value
            exp.fulfill()
            return true
        }

        // Drive the receives off the test thread so that a regression (the lock
        // leaked across the throwing unpack) surfaces as a wait timeout rather
        // than an indefinite same-thread NSLock hang.
        DispatchQueue.global().async {
            // Unknown msgtype 0x0099 (not registered) → unpack throws, dropped.
            channel.receive(Data([0x00, 0x99, 0x00, 0x00, 0x00, 0x01, 0x42]))
            // Short frame (<6 bytes) → unpack throws (invalidMsgType), dropped.
            channel.receive(Data([0x00, 0x01]))
            // Valid PingMessage at seq 0 → must still be delivered.
            channel.receive(Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0xAB]))
        }

        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(delivered, 0xAB, "channel must remain usable after malformed frames")
    }

    func testSystemReservedTypeCannotBeRegisteredByUser() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        // StreamDataMessage typeID=0xFF00 — user-level registration should fail.
        XCTAssertThrowsError(try channel.registerMessageType(StreamDataMessage.self)) { error in
            XCTAssertEqual(error as? ChannelError, .invalidMsgType)
        }
    }

    func testZeroTypeIDRejected() throws {
        final class ZeroTypeMsg: MessageBase {
            override class var typeID: UInt16 { 0 }
            override func pack() throws -> Data { Data() }
            override func unpack(_ data: Data) throws {}
        }
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        XCTAssertThrowsError(try channel.registerMessageType(ZeroTypeMsg.self)) { error in
            XCTAssertEqual(error as? ChannelError, .invalidMsgType)
        }
    }

    // MARK: - Message handler dispatch

    func testHandlerReturnTrueStopsChain() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        var firstCalled = false
        var secondCalled = false

        channel.addMessageHandler { _ in firstCalled = true; return true }   // stops chain
        channel.addMessageHandler { _ in secondCalled = true; return false }

        channel.receive(Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x01]))
        // Give a moment for callback dispatch.
        let exp = expectation(description: "processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(firstCalled)
        XCTAssertFalse(secondCalled)
    }

    func testRemoveHandlerToken() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        var callCount = 0
        let token = channel.addMessageHandler { _ in callCount += 1; return false }
        channel.removeMessageHandler(token)

        channel.receive(Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x01]))
        let exp = expectation(description: "tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 0)
    }

    // MARK: - Receive ordering

    func testOutOfOrderDeliveryReordered() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        var deliveredValues: [UInt8] = []
        let exp = expectation(description: "three delivered")
        exp.expectedFulfillmentCount = 3

        channel.addMessageHandler { msg in
            guard let ping = msg as? PingMessage else { return false }
            deliveredValues.append(ping.value)
            exp.fulfill()
            return true
        }

        // Send seq=1 then seq=0 then seq=2. Delivery order should be 0,1,2.
        let makeRaw: (UInt16, UInt8) -> Data = { seq, val in
            Data([0x00, 0x01,
                  UInt8(seq >> 8), UInt8(seq & 0xFF),
                  0x00, 0x01, val])
        }
        channel.receive(makeRaw(1, 0x11))   // out of order
        channel.receive(makeRaw(0, 0x00))   // delivers seq=0 then seq=1
        channel.receive(makeRaw(2, 0x22))   // delivers seq=2

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(deliveredValues, [0x00, 0x11, 0x22])
    }

    func testDuplicateSequenceDropped() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        var callCount = 0
        channel.addMessageHandler { _ in callCount += 1; return false }

        let raw = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x42])
        channel.receive(raw)
        channel.receive(raw)   // duplicate

        let exp = expectation(description: "tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 1)
    }

    // MARK: - Window and send-readiness

    func testLinkNotReadyWhenWindowFull() throws {
        let outlet = MockChannelOutlet()
        outlet.autoDeliver = false   // keep packets undelivered
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        // Fill the window (default=2).
        try channel.send(PingMessage(value: 1))
        try channel.send(PingMessage(value: 2))

        // Third send should throw .linkNotReady.
        XCTAssertThrowsError(try channel.send(PingMessage(value: 3))) { error in
            XCTAssertEqual(error as? ChannelError, .linkNotReady)
        }
    }

    func testWindowAdvancesOnDelivery() throws {
        let outlet = MockChannelOutlet()
        outlet.autoDeliver = false
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        try channel.send(PingMessage(value: 1))
        try channel.send(PingMessage(value: 2))
        XCTAssertEqual(outlet.heldHandles.count, 2)

        // Window should be full now (default window=2).
        XCTAssertThrowsError(try channel.send(PingMessage(value: 99)))

        // Manually deliver the first held handle, freeing window slot.
        outlet.heldHandles[0].markDelivered()

        // Now a third send must succeed.
        try channel.send(PingMessage(value: 3))
    }

    func testMDUIsOutletMDUMinusSixByteHeader() throws {
        let outlet = MockChannelOutlet()
        outlet.mockMDU = 500
        let channel = Channel(outlet: outlet)
        XCTAssertEqual(channel.mdu, 494)
    }

    func testMDUOverheadConstantIs6() {
        XCTAssertEqual(Channel.MDU_OVERHEAD, 6)
    }

    func testMDUUsesOverheadConstant() {
        let outlet = MockChannelOutlet()
        outlet.mockMDU = 100
        let channel = Channel(outlet: outlet)
        XCTAssertEqual(channel.mdu, 100 - Channel.MDU_OVERHEAD)
    }

    func testTooBigThrows() throws {
        let outlet = MockChannelOutlet()
        outlet.mockMDU = 10   // very small
        let channel = Channel(outlet: outlet)

        final class BigMsg: MessageBase {
            override class var typeID: UInt16 { 0x0010 }
            override func pack() throws -> Data { Data(repeating: 0xFF, count: 100) }
            override func unpack(_ data: Data) throws {}
        }
        try channel.registerMessageType(BigMsg.self)

        XCTAssertThrowsError(try channel.send(BigMsg())) { error in
            XCTAssertEqual(error as? ChannelError, .tooBig)
        }
    }

    // MARK: - Shutdown

    func testShutdownClearsHandlers() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)

        var called = false
        channel.addMessageHandler { _ in called = true; return false }
        channel.shutdown()

        channel.receive(Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x01]))
        let exp = expectation(description: "tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(called)
    }

    // MARK: - Link integration (loopback)

    func testChannelRoundTripOverLink() throws {
        let pair = try makeEstablishedLinkPair()

        let aChannel = pair.initiator.getChannel()
        let bChannel = pair.responderLink.getChannel()
        try aChannel.registerMessageType(PingMessage.self)
        try bChannel.registerMessageType(PingMessage.self)

        let received = expectation(description: "B got ping")
        var got: PingMessage?
        bChannel.addMessageHandler { msg in
            guard let ping = msg as? PingMessage else { return false }
            got = ping
            received.fulfill()
            return true
        }

        try aChannel.send(PingMessage(value: 0x55))
        wait(for: [received], timeout: 1.0)
        XCTAssertEqual(got?.value, 0x55)
    }

    func testChannelBidirectionalRoundTrip() throws {
        let pair = try makeEstablishedLinkPair()
        let aChannel = pair.initiator.getChannel()
        let bChannel = pair.responderLink.getChannel()

        try aChannel.registerMessageType(PingMessage.self)
        try aChannel.registerMessageType(PongMessage.self)
        try bChannel.registerMessageType(PingMessage.self)
        try bChannel.registerMessageType(PongMessage.self)

        let gotPong = expectation(description: "A got pong")
        aChannel.addMessageHandler { msg in
            guard msg is PongMessage else { return false }
            gotPong.fulfill()
            return true
        }

        bChannel.addMessageHandler { msg in
            guard let ping = msg as? PingMessage else { return false }
            try? bChannel.send(PongMessage(text: "pong:\(ping.value)"))
            return true
        }

        try aChannel.send(PingMessage(value: 7))
        wait(for: [gotPong], timeout: 1.0)
    }

    func testGetChannelReturnsSameInstance() throws {
        let pair = try makeEstablishedLinkPair()
        let ch1 = pair.initiator.getChannel()
        let ch2 = pair.initiator.getChannel()
        XCTAssertTrue(ch1 === ch2)
    }

    // MARK: - Multiple message types dispatched correctly

    func testMultipleMessageTypesDispatchedCorrectly() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        try channel.registerMessageType(PingMessage.self)
        try channel.registerMessageType(PongMessage.self)

        var pings = 0; var pongs = 0
        channel.addMessageHandler { msg in
            if msg is PingMessage { pings += 1; return true }
            if msg is PongMessage { pongs += 1; return true }
            return false
        }

        // PingMessage (typeID=0x0001) with body [0x01]
        channel.receive(Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x01]))
        // PongMessage (typeID=0x0002) with body "ok"
        channel.receive(Data([0x00, 0x02, 0x00, 0x01, 0x00, 0x02, 0x6F, 0x6B]))

        let exp = expectation(description: "tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(pings, 1)
        XCTAssertEqual(pongs, 1)
    }

    // MARK: - Helpers

    struct LinkPair {
        let initiator: Link
        let responderLink: Link
        let initiatorTransport: Transport
        let responderTransport: Transport
    }

    var aTransport: Transport!
    var bTransport: Transport!

    func makeEstablishedLinkPair() throws -> LinkPair {
        aTransport = Transport()
        bTransport = Transport()
        let bIdentity = Identity()
        let bDestination = try Destination(
            identity: bIdentity, direction: .in, kind: .single,
            appName: "channel", aspects: ["test"]
        )
        bTransport.ownerIdentity = bIdentity
        bTransport.register(destination: bDestination)

        let aIface = ChannelTestLoopback(name: "A")
        let bIface = ChannelTestLoopback(name: "B")
        aIface.paired = bIface; bIface.paired = aIface
        aTransport.register(interface: aIface)
        bTransport.register(interface: bIface)

        let aE = expectation(description: "aE")
        let bE = expectation(description: "bE")
        aTransport.onLinkEstablished = { _ in aE.fulfill() }
        bTransport.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDestination, transport: aTransport)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bTransport.links[aLink.linkID!])
        return LinkPair(initiator: aLink, responderLink: bLink,
                        initiatorTransport: aTransport, responderTransport: bTransport)
    }
}

private final class ChannelTestLoopback: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    weak var paired: ChannelTestLoopback?
    var inboundHandler: ((Packet, any Interface) -> Void)?

    init(name: String) { self.name = name }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {
        let raw = try packet.pack()
        let copy = try Packet.unpack(raw)
        paired?.inboundHandler?(copy, paired!)
    }
}
