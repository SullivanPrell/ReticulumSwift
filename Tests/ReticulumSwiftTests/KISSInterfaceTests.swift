import XCTest
@testable import ReticulumSwift

// MARK: - KISSConstantsTests

final class KISSConstantsTests: XCTestCase {

    func testFend()           { XCTAssertEqual(KISS.fend,           0xC0) }
    func testFesc()           { XCTAssertEqual(KISS.fesc,           0xDB) }
    func testTfend()          { XCTAssertEqual(KISS.tfend,          0xDC) }
    func testTfesc()          { XCTAssertEqual(KISS.tfesc,          0xDD) }
    func testCmdData()        { XCTAssertEqual(KISS.cmdData,        0x00) }
    func testCmdTxDelay()     { XCTAssertEqual(KISS.cmdTxDelay,     0x01) }
    func testCmdP()           { XCTAssertEqual(KISS.cmdP,           0x02) }
    func testCmdSlotTime()    { XCTAssertEqual(KISS.cmdSlotTime,    0x03) }
    func testCmdTxTail()      { XCTAssertEqual(KISS.cmdTxTail,      0x04) }
    func testCmdReady()       { XCTAssertEqual(KISS.cmdReady,       0x0F) }
    func testCmdReturn()      { XCTAssertEqual(KISS.cmdReturn,      0xFF) }
}

// MARK: - KISSEscapeTests

final class KISSEscapeTests: XCTestCase {

    func testEscapeFesc() {
        // 0xDB → [0xDB, 0xDD]
        let input = Data([0xDB])
        XCTAssertEqual(KISS.escape(input), Data([0xDB, 0xDD]))
    }

    func testEscapeFend() {
        // 0xC0 → [0xDB, 0xDC]
        let input = Data([0xC0])
        XCTAssertEqual(KISS.escape(input), Data([0xDB, 0xDC]))
    }

    func testEscapeNoChange() {
        let input = Data([0x01, 0x7E, 0xFF])
        XCTAssertEqual(KISS.escape(input), input)
    }

    func testEscapeMixed() {
        // [0xDB, 0xC0] → [0xDB, 0xDD, 0xDB, 0xDC]
        let input = Data([0xDB, 0xC0])
        XCTAssertEqual(KISS.escape(input), Data([0xDB, 0xDD, 0xDB, 0xDC]))
    }

    func testFrameHasFendDelimiters() {
        let data  = Data([0x01, 0x02])
        let frame = KISS.frame(data)
        XCTAssertEqual(frame.first, KISS.fend)
        XCTAssertEqual(frame.last,  KISS.fend)
    }

    func testFrameHasCmdDataAfterFirstFend() {
        let frame = KISS.frame(Data([0xAA]))
        XCTAssertEqual(frame[1], KISS.cmdData)
    }

    func testFramePayloadEscaped() {
        // Payload with 0xC0 — should be escaped in the frame
        let frame = KISS.frame(Data([0xC0]))
        // Expected: FEND + CMD_DATA + FESC + TFEND + FEND
        XCTAssertEqual(frame, Data([KISS.fend, KISS.cmdData, KISS.fesc, KISS.tfend, KISS.fend]))
    }
}

// MARK: - KISSFrameDecoderTests

final class KISSFrameDecoderTests: XCTestCase {

    func testDecodeDataFrame() {
        let decoder = KISS.FrameDecoder()
        // FEND + CMD_DATA + 0xAA + 0xBB + FEND
        let bytes = Data([KISS.fend, KISS.cmdData, 0xAA, 0xBB, KISS.fend])
        let frames = decoder.feed(bytes)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].command, KISS.cmdData)
        XCTAssertEqual(frames[0].data, Data([0xAA, 0xBB]))
    }

    func testDecodeFescUnescape() {
        let decoder = KISS.FrameDecoder()
        // Payload contains 0xC0 escaped as [FESC, TFEND]
        let bytes = Data([KISS.fend, KISS.cmdData,
                          KISS.fesc, KISS.tfend,  // represents 0xC0
                          KISS.fend])
        let frames = decoder.feed(bytes)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].data, Data([KISS.fend]))
    }

    func testDecodeWithFescUnescapeForFesc() {
        let decoder = KISS.FrameDecoder()
        // 0xDB escaped as [FESC, TFESC]
        let bytes = Data([KISS.fend, KISS.cmdData,
                          KISS.fesc, KISS.tfesc,   // represents 0xDB
                          KISS.fend])
        let frames = decoder.feed(bytes)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].data, Data([KISS.fesc]))
    }

    func testDecodeTwoFramesBackToBack() {
        let decoder = KISS.FrameDecoder()
        let f1 = KISS.frame(Data([0x01]))
        let f2 = KISS.frame(Data([0x02]))
        let frames = decoder.feed(f1 + f2)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].data, Data([0x01]))
        XCTAssertEqual(frames[1].data, Data([0x02]))
    }

    func testCmdReadyFrame() {
        let decoder = KISS.FrameDecoder()
        // FEND + CMD_READY + 0x01 + FEND  (standard flow-control ready frame)
        let bytes = Data([KISS.fend, KISS.cmdReady, 0x01, KISS.fend])
        let frames = decoder.feed(bytes)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].command, KISS.cmdReady)
    }

    func testConsecutiveFendsAreHarmless() {
        let decoder = KISS.FrameDecoder()
        // Two consecutive FENDs followed by a real frame
        let bytes = Data([KISS.fend, KISS.fend]) + KISS.frame(Data([0x42]))
        let frames = decoder.feed(bytes)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].data, Data([0x42]))
    }

    func testResetClearsState() {
        let decoder = KISS.FrameDecoder()
        // Start a partial frame
        _ = decoder.feed(Data([KISS.fend, KISS.cmdData, 0xAA]))
        decoder.reset()
        // After reset, a new frame should decode cleanly
        let frames = decoder.feed(KISS.frame(Data([0xBB])))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].data, Data([0xBB]))
    }
}

// MARK: - KISSInterfaceConstantsTests

final class KISSInterfaceConstantsTests: XCTestCase {

    func testBitrateGuess()    { XCTAssertEqual(KISSInterface.bitrateGuess,    1_200) }
    func testDefaultIfacSize() { XCTAssertEqual(KISSInterface.defaultIfacSize,     8) }
    func testHwMtu()           { XCTAssertEqual(KISSInterface.hwMtuConstant,     564) }
}

// MARK: - KISSInterfaceInitTests

final class KISSInterfaceInitTests: XCTestCase {

    func makeIface(flowControl: Bool = false) -> (KISSInterface, MockSerialPort) {
        let t = MockSerialPort()
        let i = KISSInterface(name: "KISS0", port: "/dev/tty.usb",
                               transport: t)
        return (i, t)
    }

    func testName()            { XCTAssertEqual(makeIface().0.name, "KISS0")  }
    func testOfflineAtInit()   { XCTAssertFalse(makeIface().0.isOnline)       }
    func testDefaultPreamble() { XCTAssertEqual(makeIface().0.preamble,   350) }
    func testDefaultTxtail()   { XCTAssertEqual(makeIface().0.txtail,      20) }
    func testDefaultPersistence(){ XCTAssertEqual(makeIface().0.persistence, 64) }
    func testDefaultSlottime() { XCTAssertEqual(makeIface().0.slottime,    20) }
    func testDefaultFlowControlOff() { XCTAssertFalse(makeIface().0.flowControl) }
    func testHwMtuProperty()   { XCTAssertEqual(makeIface().0.hwMtu,       564) }
    func testBitrateDefault()  { XCTAssertEqual(makeIface().0.bitrate,   1_200) }
}

// MARK: - KISSInterfaceLifecycleTests

final class KISSInterfaceLifecycleTests: XCTestCase {

    func testStartGoesOnline() throws {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x", transport: t)
        try i.start()
        XCTAssertTrue(i.isOnline)
        XCTAssertTrue(t.isOpen)
    }

    func testStopGoesOffline() throws {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x", transport: t)
        try i.start()
        i.stop()
        XCTAssertFalse(i.isOnline)
        XCTAssertFalse(t.isOpen)
    }

    func testInterfaceReadyAfterStart() throws {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x", transport: t)
        try i.start()
        XCTAssertTrue(i.interfaceReady)
    }
}

// MARK: - KISSConfigCommandTests

final class KISSConfigCommandTests: XCTestCase {

    func startedInterface() throws -> (KISSInterface, MockSerialPort) {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x",
                               preamble: 350, txtail: 20,
                               persistence: 64, slottime: 20,
                               transport: t)
        try i.start()
        return (i, t)
    }

    /// All writes during start: setPreamble + setTxTail + setPersistence + setSlotTime + setFlowControl
    func testStartSendsFiveConfigCommands() throws {
        let (_, t) = try startedInterface()
        XCTAssertEqual(t.writtenData.count, 5)
    }

    func testPreambleCommand() throws {
        let (_, t) = try startedInterface()
        // preamble=350 → 350/10=35 → [FEND, CMD_TXDELAY, 35, FEND]
        XCTAssertEqual(t.writtenData[0], Data([KISS.fend, KISS.cmdTxDelay, 35, KISS.fend]))
    }

    func testTxTailCommand() throws {
        let (_, t) = try startedInterface()
        // txtail=20 → 20/10=2 → [FEND, CMD_TXTAIL, 2, FEND]
        XCTAssertEqual(t.writtenData[1], Data([KISS.fend, KISS.cmdTxTail, 2, KISS.fend]))
    }

    func testPersistenceCommand() throws {
        let (_, t) = try startedInterface()
        // persistence=64 → [FEND, CMD_P, 64, FEND]
        XCTAssertEqual(t.writtenData[2], Data([KISS.fend, KISS.cmdP, 64, KISS.fend]))
    }

    func testSlotTimeCommand() throws {
        let (_, t) = try startedInterface()
        // slottime=20 → 20/10=2 → [FEND, CMD_SLOTTIME, 2, FEND]
        XCTAssertEqual(t.writtenData[3], Data([KISS.fend, KISS.cmdSlotTime, 2, KISS.fend]))
    }

    func testFlowControlCommand() throws {
        let (_, t) = try startedInterface()
        // setFlowControl → [FEND, CMD_READY, 0x01, FEND]
        XCTAssertEqual(t.writtenData[4], Data([KISS.fend, KISS.cmdReady, 0x01, KISS.fend]))
    }
}

// MARK: - KISSInterfaceOutgoingTests

final class KISSInterfaceOutgoingTests: XCTestCase {

    func makeStarted() throws -> (KISSInterface, MockSerialPort) {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x", transport: t)
        try i.start()
        t.writtenData.removeAll()
        return (i, t)
    }

    func testKISSFrameWhenOnline() throws {
        let (i, t) = try makeStarted()
        i.processOutgoing(Data([0xAA, 0xBB]))
        let written = try XCTUnwrap(t.writtenData.first)
        XCTAssertEqual(written.first, KISS.fend)
        XCTAssertEqual(written.last,  KISS.fend)
        XCTAssertEqual(written[1],    KISS.cmdData)
    }

    func testNotSentWhenOffline() throws {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x", transport: t)
        i.processOutgoing(Data([0x01]))
        XCTAssertTrue(t.writtenData.isEmpty)
    }

    func testTxBytesCountsOriginalPayload() throws {
        let (i, _) = try makeStarted()
        let payload = Data([0x01, 0x02, 0x03])
        i.processOutgoing(payload)
        XCTAssertEqual(i.txBytes, payload.count)   // not framed count
    }

    func testNotReadyQueuesPacket() throws {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x",
                               flowControl: true, transport: t)
        try i.start()
        t.writtenData.removeAll()

        // First send: should go through but set interfaceReady=false
        i.processOutgoing(Data([0x01]))
        XCTAssertFalse(i.interfaceReady)

        // Second send: interfaceReady=false → queued
        i.processOutgoing(Data([0x02]))
        XCTAssertEqual(i.queuedPacketCount, 1)
    }

    func testProcessQueueDrainsQueue() throws {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x",
                               flowControl: true, transport: t)
        try i.start()
        t.writtenData.removeAll()

        // Send 1: goes through, sets interfaceReady=false
        i.processOutgoing(Data([0x01]))
        // Send 2: queued
        i.processOutgoing(Data([0x02]))
        XCTAssertEqual(i.queuedPacketCount, 1)

        // Simulate CMD_READY from TNC
        i.processQueue()
        XCTAssertEqual(i.queuedPacketCount, 0)
    }

    func testCmdReadyFrameTriggerQueue() throws {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x",
                               flowControl: true, transport: t)
        try i.start()
        t.writtenData.removeAll()

        // Force not ready + queue a packet
        i.processOutgoing(Data([0x01]))  // sends, sets not ready
        i.processOutgoing(Data([0x02]))  // queued
        XCTAssertEqual(i.queuedPacketCount, 1)

        // Inject CMD_READY from TNC
        let readyFrame = Data([KISS.fend, KISS.cmdReady, 0x01, KISS.fend])
        i.feedBytes(readyFrame)
        XCTAssertEqual(i.queuedPacketCount, 0)
    }
}

// MARK: - KISSInterfaceIncomingTests

final class KISSInterfaceIncomingTests: XCTestCase {

    func testDataFrameDeliveredToRawHandler() throws {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x", transport: t)
        var received: Data?
        i.rawInboundHandler = { data, _ in received = data }

        let frame = KISS.frame(Data([0xDE, 0xAD]))
        i.feedBytes(frame)

        XCTAssertEqual(received, Data([0xDE, 0xAD]))
    }

    func testRxBytesIncrements() throws {
        let t = MockSerialPort()
        let i = KISSInterface(name: "K", port: "/dev/x", transport: t)
        i.rawInboundHandler = { _, _ in }

        let payload = Data([0x01, 0x02])
        i.feedBytes(KISS.frame(payload))
        XCTAssertEqual(i.rxBytes, payload.count)
    }
}

// MARK: - AX25ConstantsTests

final class AX25ConstantsTests: XCTestCase {

    func testHeaderSize()    { XCTAssertEqual(AX25.headerSize,    16)   }
    func testPidNoLayer3()   { XCTAssertEqual(AX25.pidNoLayer3,   0xF0) }
    func testCtrlUI()        { XCTAssertEqual(AX25.ctrlUI,        0x03) }
    func testCrcCorrect()    { XCTAssertEqual(AX25.crcCorrect,    Data([0xF0, 0xB8])) }
    func testDstCallsign()   { XCTAssertEqual(AX25.dstCallsign,   "APZRNS") }
}

// MARK: - AX25AddressEncodingTests

final class AX25AddressEncodingTests: XCTestCase {

    func testDstCallsignEncoding() {
        // "APZRNS" (6 chars) → each byte left-shifted 1
        let encoded = AX25.encodeAddress(callsign: "APZRNS", ssid: 0, endOfAddress: false)
        XCTAssertEqual(encoded.count, 7)
        XCTAssertEqual(encoded[0], UInt8(ascii: "A") << 1)  // 0x82
        XCTAssertEqual(encoded[1], UInt8(ascii: "P") << 1)  // 0xA0
        XCTAssertEqual(encoded[2], UInt8(ascii: "Z") << 1)  // 0xB4
        XCTAssertEqual(encoded[3], UInt8(ascii: "R") << 1)  // 0xA4
        XCTAssertEqual(encoded[4], UInt8(ascii: "N") << 1)  // 0x9C
        XCTAssertEqual(encoded[5], UInt8(ascii: "S") << 1)  // 0xA6
        XCTAssertEqual(encoded[6], 0x60)                    // ssid=0, no end-of-addr
    }

    func testSrcCallsignShortPadded() {
        // "TEST" (4 chars) → 4 shifted + 2 padding spaces (0x20<<1=0x40)
        let encoded = AX25.encodeAddress(callsign: "TEST", ssid: 0, endOfAddress: true)
        XCTAssertEqual(encoded.count, 7)
        XCTAssertEqual(encoded[0], UInt8(ascii: "T") << 1)
        XCTAssertEqual(encoded[1], UInt8(ascii: "E") << 1)
        XCTAssertEqual(encoded[2], UInt8(ascii: "S") << 1)
        XCTAssertEqual(encoded[3], UInt8(ascii: "T") << 1)
        XCTAssertEqual(encoded[4], 0x20 << 1)  // space padding
        XCTAssertEqual(encoded[5], 0x20 << 1)
    }

    func testSrcSSIDEndOfAddressBit() {
        // ssid=3, end-of-address → 0x60 | (3<<1) | 0x01 = 0x60 | 0x06 | 0x01 = 0x67
        let encoded = AX25.encodeAddress(callsign: "TEST", ssid: 3, endOfAddress: true)
        let ssidByte = encoded[6]
        XCTAssertEqual(ssidByte, 0x60 | UInt8(3 << 1) | 0x01)  // 0x67
    }

    func testSrcSSIDNoEndBit() {
        // ssid=0, endOfAddress=false → 0x60
        let encoded = AX25.encodeAddress(callsign: "TEST", ssid: 0, endOfAddress: false)
        XCTAssertEqual(encoded[6], 0x60)
    }

    func testFullHeaderSize() {
        let dst = AX25.encodeAddress(callsign: "APZRNS", ssid: 0, endOfAddress: false)
        let src = AX25.encodeAddress(callsign: "TEST",   ssid: 0, endOfAddress: true)
        var hdr = Data()
        hdr.append(dst); hdr.append(src)
        hdr.append(AX25.ctrlUI); hdr.append(AX25.pidNoLayer3)
        XCTAssertEqual(hdr.count, AX25.headerSize)
    }
}

// MARK: - AX25KISSInterfaceConstantsTests

final class AX25KISSInterfaceConstantsTests: XCTestCase {

    func testBitrateGuess()    { XCTAssertEqual(AX25KISSInterface.bitrateGuess,    1_200) }
    func testDefaultIfacSize() { XCTAssertEqual(AX25KISSInterface.defaultIfacSize,     8) }
    func testHwMtu()           { XCTAssertEqual(AX25KISSInterface.hwMtuConstant,     564) }
}

// MARK: - AX25KISSInterfaceCallsignValidationTests

final class AX25KISSInterfaceCallsignValidationTests: XCTestCase {

    func makeTransport() -> MockSerialPort { MockSerialPort() }

    func testValidCallsignAndSSID() throws {
        let iface = try AX25KISSInterface(name: "AX", port: "/dev/x",
                                           callsign: "TEST", ssid: 5,
                                           transport: makeTransport())
        XCTAssertEqual(iface.srcCallsign, "TEST")
        XCTAssertEqual(iface.srcSSID,     5)
    }

    func testCallsignUpercased() throws {
        let iface = try AX25KISSInterface(name: "AX", port: "/dev/x",
                                           callsign: "kc1abc", ssid: 0,
                                           transport: makeTransport())
        XCTAssertEqual(iface.srcCallsign, "KC1ABC")
    }

    func testTooShortCallsignThrows() {
        XCTAssertThrowsError(
            try AX25KISSInterface(name: "AX", port: "/dev/x",
                                   callsign: "AB", ssid: 0,
                                   transport: makeTransport())
        )
    }

    func testTooLongCallsignThrows() {
        XCTAssertThrowsError(
            try AX25KISSInterface(name: "AX", port: "/dev/x",
                                   callsign: "TOOLONG", ssid: 0,
                                   transport: makeTransport())
        )
    }

    func testSSIDTooLowThrows() {
        XCTAssertThrowsError(
            try AX25KISSInterface(name: "AX", port: "/dev/x",
                                   callsign: "TEST", ssid: -1,
                                   transport: makeTransport())
        )
    }

    func testSSIDTooHighThrows() {
        XCTAssertThrowsError(
            try AX25KISSInterface(name: "AX", port: "/dev/x",
                                   callsign: "TEST", ssid: 16,
                                   transport: makeTransport())
        )
    }

    func testSSIDBoundaries() throws {
        // SSID 0 and 15 are both valid
        _ = try AX25KISSInterface(name: "AX", port: "/dev/x",
                                   callsign: "TEST", ssid: 0,
                                   transport: makeTransport())
        _ = try AX25KISSInterface(name: "AX", port: "/dev/x",
                                   callsign: "TEST", ssid: 15,
                                   transport: makeTransport())
    }
}

// MARK: - AX25KISSInterfaceOutgoingTests

final class AX25KISSInterfaceOutgoingTests: XCTestCase {

    func makeStarted(callsign: String = "TEST", ssid: Int = 0)
            throws -> (AX25KISSInterface, MockSerialPort) {
        let t = MockSerialPort()
        let i = try AX25KISSInterface(name: "AX", port: "/dev/x",
                                       callsign: callsign, ssid: ssid,
                                       transport: t)
        try i.start()
        t.writtenData.removeAll()
        return (i, t)
    }

    func testOutgoingHasAX25Header() throws {
        let (i, t) = try makeStarted()
        i.processOutgoing(Data([0xBE, 0xEF]))
        let written = try XCTUnwrap(t.writtenData.first)

        // Decode the KISS frame to get the inner payload
        let decoder = KISS.FrameDecoder()
        let frames  = decoder.feed(written)
        XCTAssertEqual(frames.count, 1)

        let inner = frames[0].data
        // First 16 bytes should be AX.25 header
        XCTAssertGreaterThanOrEqual(inner.count, AX25.headerSize + 2)
        // Bytes at offset 14: CTRL_UI
        XCTAssertEqual(inner[14], AX25.ctrlUI)
        // Bytes at offset 15: PID_NOLAYER3
        XCTAssertEqual(inner[15], AX25.pidNoLayer3)
    }

    func testOutgoingPayloadAppenedAfterHeader() throws {
        let (i, t) = try makeStarted()
        let payload = Data([0xCA, 0xFE])
        i.processOutgoing(payload)
        let written = try XCTUnwrap(t.writtenData.first)

        let decoder = KISS.FrameDecoder()
        let frames  = decoder.feed(written)
        let inner   = frames[0].data
        let stripped = inner.dropFirst(AX25.headerSize)
        XCTAssertEqual(Data(stripped), payload)
    }

    func testTxBytesCountsOriginalPayload() throws {
        let (i, _) = try makeStarted()
        let payload = Data([0x01, 0x02, 0x03])
        i.processOutgoing(payload)
        XCTAssertEqual(i.txBytes, payload.count)
    }

    func testDstCallsignIsAPZRNS() throws {
        let (i, t) = try makeStarted()
        i.processOutgoing(Data([0x01]))
        let written = try XCTUnwrap(t.writtenData.first)

        let decoder = KISS.FrameDecoder()
        let frames  = decoder.feed(written)
        let inner   = frames[0].data

        // First 7 bytes: dst addr — each char of "APZRNS" shifted left 1
        let dstBytes = Array(inner[0..<6])
        let expected = "APZRNS".utf8.map { $0 << 1 }
        XCTAssertEqual(dstBytes, expected)
    }
}

// MARK: - AX25KISSInterfaceIncomingTests

final class AX25KISSInterfaceIncomingTests: XCTestCase {

    func testIncomingStripsAX25Header() throws {
        let t = MockSerialPort()
        let i = try AX25KISSInterface(name: "AX", port: "/dev/x",
                                       callsign: "TEST", ssid: 0,
                                       transport: t)
        var received: Data?
        i.rawInboundHandler = { data, _ in received = data }

        let payload  = Data([0xBE, 0xEF])
        // Build a fake AX.25 UI frame with 16-byte header + payload
        let header   = Data(repeating: 0x00, count: AX25.headerSize)
        let kissFrame = KISS.frame(header + payload)
        i.feedBytes(kissFrame)

        XCTAssertEqual(received, payload)
    }

    func testIncomingTooShortIgnored() throws {
        let t = MockSerialPort()
        let i = try AX25KISSInterface(name: "AX", port: "/dev/x",
                                       callsign: "TEST", ssid: 0,
                                       transport: t)
        var received: Data?
        i.rawInboundHandler = { data, _ in received = data }

        // Frame with only 8 bytes — shorter than AX25.headerSize (16)
        let kissFrame = KISS.frame(Data(repeating: 0x00, count: 8))
        i.feedBytes(kissFrame)

        XCTAssertNil(received)
    }

    func testRxBytesCountsFullPayloadIncludingHeader() throws {
        let t = MockSerialPort()
        let i = try AX25KISSInterface(name: "AX", port: "/dev/x",
                                       callsign: "TEST", ssid: 0,
                                       transport: t)
        i.rawInboundHandler = { _, _ in }

        let inner = Data(repeating: 0x00, count: AX25.headerSize + 5)
        i.feedBytes(KISS.frame(inner))
        // rxBytes should count full inner frame (header + payload)
        XCTAssertEqual(i.rxBytes, inner.count)
    }
}
