import XCTest
@testable import ReticulumSwift

// MARK: - MockSerialPort

/// In-memory serial port for unit testing.  Tracks all writes; read callbacks
/// are driven by `simulateReceive`.
final class MockSerialPort: SerialPortTransport {
    var isOpen = false
    var openCallCount = 0
    var closeCallCount = 0
    var writtenData: [Data] = []
    var shouldThrowOnOpen = false
    private var readCallback: ((Data) -> Void)?

    func open(port: String, baudRate: Int, dataBits: Int,
              parity: SerialParity, stopBits: Int) throws {
        if shouldThrowOnOpen {
            throw SerialInterfaceError.portOpenFailed(port)
        }
        isOpen = true
        openCallCount += 1
    }

    func close() {
        isOpen = false
        closeCallCount += 1
    }

    @discardableResult
    func write(_ data: Data) throws -> Int {
        writtenData.append(data)
        return data.count
    }

    func setReadCallback(_ callback: @escaping (Data) -> Void) {
        readCallback = callback
    }

    /// Inject bytes as if they arrived from the serial port.
    func simulateReceive(_ data: Data) {
        readCallback?(data)
    }
}

// MARK: - SerialParityTests

final class SerialParityTests: XCTestCase {

    func testNoneFromN()        { XCTAssertEqual(SerialParity(string: "N"),    .none) }
    func testNoneFromLowerN()   { XCTAssertEqual(SerialParity(string: "n"),    .none) }
    func testNoneFromUnknown()  { XCTAssertEqual(SerialParity(string: "X"),    .none) }
    func testEvenFromE()        { XCTAssertEqual(SerialParity(string: "e"),    .even) }
    func testEvenFromUpperE()   { XCTAssertEqual(SerialParity(string: "E"),    .even) }
    func testEvenFromFull()     { XCTAssertEqual(SerialParity(string: "even"), .even) }
    func testOddFromO()         { XCTAssertEqual(SerialParity(string: "o"),    .odd)  }
    func testOddFromUpperO()    { XCTAssertEqual(SerialParity(string: "O"),    .odd)  }
    func testOddFromFull()      { XCTAssertEqual(SerialParity(string: "odd"),  .odd)  }
}

// MARK: - SerialInterfaceConstantsTests

final class SerialInterfaceConstantsTests: XCTestCase {

    func testMaxChunk() {
        XCTAssertEqual(SerialInterface.maxChunk, 32_768)
    }

    func testDefaultIfacSize() {
        XCTAssertEqual(SerialInterface.defaultIfacSize, 8)
    }

    func testHwMtuConstant() {
        XCTAssertEqual(SerialInterface.hwMtuConstant, 564)
    }
}

// MARK: - SerialInterfaceInitTests

final class SerialInterfaceInitTests: XCTestCase {

    var transport: MockSerialPort!
    var iface: SerialInterface!

    override func setUp() {
        super.setUp()
        transport = MockSerialPort()
        iface = SerialInterface(name: "Serial0",
                                port: "/dev/ttyUSB0",
                                transport: transport)
    }

    func testName()           { XCTAssertEqual(iface.name, "Serial0")        }
    func testPort()           { XCTAssertEqual(iface.port, "/dev/ttyUSB0")  }
    func testDefaultSpeed()   { XCTAssertEqual(iface.speed,    9_600)        }
    func testDefaultDataBits(){ XCTAssertEqual(iface.dataBits, 8)            }
    func testDefaultParity()  { XCTAssertEqual(iface.parity,  .none)         }
    func testDefaultStopBits(){ XCTAssertEqual(iface.stopBits, 1)            }
    func testOfflineAtInit()  { XCTAssertFalse(iface.isOnline)               }
    func testHwMtuProperty()  { XCTAssertEqual(iface.hwMtu, 564)             }

    func testBitrateEqualsSpeed() {
        XCTAssertEqual(iface.bitrate, iface.speed)
    }

    func testCustomSpeed() {
        let fast = SerialInterface(name: "S", port: "/dev/x",
                                   speed: 115_200, transport: transport)
        XCTAssertEqual(fast.speed,   115_200)
        XCTAssertEqual(fast.bitrate, 115_200)
    }

    func testStringParityConvenience() {
        let evenIface = SerialInterface(name: "S", port: "/dev/x",
                                        parityString: "even", transport: transport)
        XCTAssertEqual(evenIface.parity, .even)
    }
}

// MARK: - SerialInterfaceLifecycleTests

final class SerialInterfaceLifecycleTests: XCTestCase {

    func testStartOpensPortAndGoesOnline() throws {
        let t = MockSerialPort()
        let iface = SerialInterface(name: "S", port: "/dev/x", transport: t)
        try iface.start()
        XCTAssertTrue(iface.isOnline)
        XCTAssertTrue(t.isOpen)
        XCTAssertEqual(t.openCallCount, 1)
    }

    func testStopClosesPortAndGoesOffline() throws {
        let t = MockSerialPort()
        let iface = SerialInterface(name: "S", port: "/dev/x", transport: t)
        try iface.start()
        iface.stop()
        XCTAssertFalse(iface.isOnline)
        XCTAssertFalse(t.isOpen)
    }

    func testStartThrowsWhenPortFails() {
        let t = MockSerialPort()
        t.shouldThrowOnOpen = true
        let iface = SerialInterface(name: "S", port: "/dev/x", transport: t)
        XCTAssertThrowsError(try iface.start())
        XCTAssertFalse(iface.isOnline)
    }
}

// MARK: - SerialInterfaceOutgoingTests

final class SerialInterfaceOutgoingTests: XCTestCase {

    func makeOnlineInterface() throws -> (SerialInterface, MockSerialPort) {
        let t = MockSerialPort()
        let iface = SerialInterface(name: "S", port: "/dev/x", transport: t)
        try iface.start()
        t.writtenData.removeAll()  // clear any setup writes
        return (iface, t)
    }

    func testHDLCFrameHasFlagDelimiters() throws {
        let (iface, t) = try makeOnlineInterface()
        iface.processOutgoing(Data([0x01, 0x02, 0x03]))
        let written = try XCTUnwrap(t.writtenData.first)
        XCTAssertEqual(written.first, HDLC.flag)
        XCTAssertEqual(written.last,  HDLC.flag)
    }

    func testHDLCFlagByteInPayloadIsEscaped() throws {
        let (iface, t) = try makeOnlineInterface()
        iface.processOutgoing(Data([HDLC.flag]))
        let written = try XCTUnwrap(t.writtenData.first)
        // Middle bytes should be ESC + (FLAG ^ ESC_MASK)
        let middle = written.dropFirst().dropLast()
        XCTAssertEqual(middle, Data([HDLC.esc, HDLC.flag ^ HDLC.escMask]))
    }

    func testNotSentWhenOffline() {
        let t = MockSerialPort()
        let iface = SerialInterface(name: "S", port: "/dev/x", transport: t)
        // isOnline = false (not started)
        iface.processOutgoing(Data([0xFF]))
        XCTAssertTrue(t.writtenData.isEmpty)
    }

    func testTxBytesCountsFramedBytes() throws {
        let (iface, t) = try makeOnlineInterface()
        let payload = Data([0xAA, 0xBB])
        iface.processOutgoing(payload)
        let framed = try XCTUnwrap(t.writtenData.first)
        XCTAssertEqual(iface.txBytes, framed.count)
    }

    func testTxPacketsIncrement() throws {
        let (iface, _) = try makeOnlineInterface()
        iface.processOutgoing(Data([0x01]))
        iface.processOutgoing(Data([0x02]))
        XCTAssertEqual(iface.txPackets, 2)
    }
}

// MARK: - SerialInterfaceIncomingTests

final class SerialInterfaceIncomingTests: XCTestCase {

    func testDecodedFrameDeliveredToRawHandler() throws {
        let t = MockSerialPort()
        let iface = SerialInterface(name: "S", port: "/dev/x", transport: t)
        var received: Data?
        iface.rawInboundHandler = { data, _ in received = data }

        let payload = Data([0xAA, 0xBB, 0xCC])
        iface.feedBytes(HDLC.frame(payload))

        XCTAssertEqual(received, payload)
    }

    func testMultipleFramesDecodedInOneCall() throws {
        let t = MockSerialPort()
        let iface = SerialInterface(name: "S", port: "/dev/x", transport: t)
        var received: [Data] = []
        iface.rawInboundHandler = { data, _ in received.append(data) }

        let f1 = HDLC.frame(Data([0x01]))
        let f2 = HDLC.frame(Data([0x02]))
        iface.feedBytes(f1 + f2)

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0], Data([0x01]))
        XCTAssertEqual(received[1], Data([0x02]))
    }

    func testRxBytesCountsPayloadBytes() throws {
        let t = MockSerialPort()
        let iface = SerialInterface(name: "S", port: "/dev/x", transport: t)
        iface.rawInboundHandler = { _, _ in }

        let payload = Data([0x01, 0x02, 0x03])
        iface.feedBytes(HDLC.frame(payload))
        XCTAssertEqual(iface.rxBytes, payload.count)
    }

    func testRxPacketsIncrement() throws {
        let t = MockSerialPort()
        let iface = SerialInterface(name: "S", port: "/dev/x", transport: t)
        iface.rawInboundHandler = { _, _ in }

        iface.feedBytes(HDLC.frame(Data([0x01])))
        iface.feedBytes(HDLC.frame(Data([0x02])))
        XCTAssertEqual(iface.rxPackets, 2)
    }

    func testReadCallbackFeedsDecoder() throws {
        let t = MockSerialPort()
        let iface = SerialInterface(name: "S", port: "/dev/x", transport: t)
        var received: Data?
        iface.rawInboundHandler = { data, _ in received = data }
        try iface.start()

        let payload = Data([0xDE, 0xAD])
        t.simulateReceive(HDLC.frame(payload))

        XCTAssertEqual(received, payload)
    }
}
