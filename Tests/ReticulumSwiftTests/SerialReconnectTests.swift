import XCTest
@testable import ReticulumSwift

/// Python detects device loss from its blocking read loop raising, then redials forever at 5 s:
/// `SerialInterface.py:196-221`, `KISSInterface.py:365-380`, `AX25KISSInterface.py:378-393`,
/// `RNodeInterface.py:1155-1187` — and an RNode even retries a failed *initial* open in a
/// daemon thread (`:354-361`). The port had no equivalent at any layer: the transport seams had
/// no error surface, `POSIXSerialPort` silently discarded device-gone reads and never checked
/// `write()`'s -1, no serial-family interface ever went offline except explicit `stop()`, and
/// the `reconnectWait` constants were dead code pinned by constant-value tests. After a USB
/// flap the interface stayed Up with growing TX counters while every packet went into a dead
/// fd — where a Python node resumes within ~5 s.
final class SerialReconnectTests: XCTestCase {

    private struct DeviceGone: Error {}

    private final class FlappableSerialPort: SerialPortTransport {
        var isOpen = false
        var onTransportError: ((Error) -> Void)?
        var failWrites = false
        var failNextOpens = 0
        private(set) var openCount = 0
        private(set) var readCallback: ((Data) -> Void)?

        func open(port: String, baudRate: Int, dataBits: Int,
                  parity: SerialParity, stopBits: Int) throws {
            openCount += 1
            if failNextOpens > 0 { failNextOpens -= 1; throw DeviceGone() }
            isOpen = true
        }
        func close() { isOpen = false }
        @discardableResult func write(_ data: Data) throws -> Int {
            if failWrites {
                let error = DeviceGone()
                onTransportError?(error)
                throw error
            }
            return data.count
        }
        func setReadCallback(_ callback: @escaping (Data) -> Void) { readCallback = callback }

        /// The USB cable is yanked: the read side reports the device gone.
        func flap() {
            isOpen = false
            onTransportError?(DeviceGone())
        }
    }

    private func makePacket() -> Packet {
        Packet(destinationType: .single, packetType: .data,
               destinationHash: Data(repeating: 0x0A, count: 16),
               context: .none, data: Data(repeating: 0xFF, count: 8))
    }

    // MARK: - Loss is noticed

    func testDeviceLossTakesASerialInterfaceOffline() throws {
        let port = FlappableSerialPort()
        let iface = SerialInterface(name: "ser", port: "/dev/test", transport: port)
        try iface.start()
        XCTAssertTrue(iface.isOnline)

        port.flap()
        XCTAssertFalse(iface.isOnline,
                       """
                       the interface stayed Up after its device vanished — Python's read loop \
                       raises and sets online = False (SerialInterface.py:196-200); an Up \
                       interface with a dead fd silently blackholes everything Transport \
                       routes to it, while rnstatus shows healthy growing counters
                       """)
    }

    func testDeviceLossTakesAKISSInterfaceOffline() throws {
        let port = FlappableSerialPort()
        let iface = KISSInterface(name: "kiss", port: "/dev/test", transport: port)
        try iface.start()
        XCTAssertTrue(iface.isOnline)
        port.flap()
        XCTAssertFalse(iface.isOnline, "KISSInterface.py:365-369 — same loop, same teardown")
    }

    func testDeviceLossTakesAnAX25InterfaceOffline() throws {
        let port = FlappableSerialPort()
        let iface = try AX25KISSInterface(name: "ax25", port: "/dev/test",
                                          callsign: "NO1CLL", ssid: 0, transport: port)
        try iface.start()
        XCTAssertTrue(iface.isOnline)
        port.flap()
        XCTAssertFalse(iface.isOnline, "AX25KISSInterface.py:378-382 — same loop, same teardown")
    }

    // MARK: - Loss is recovered from

    func testASerialInterfaceRedialsAfterLoss() throws {
        let port = FlappableSerialPort()
        let iface = SerialInterface(name: "ser", port: "/dev/test", transport: port)
        iface.reconnectWait = 0.05
        try iface.start()
        port.flap()

        let deadline = Date().addingTimeInterval(2.0)
        while !iface.isOnline && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertTrue(iface.isOnline,
                      "no redial ever happened — Python's reconnect_port loop retries every "
                      + "5 s until the device answers (SerialInterface.py:203-221)")
        XCTAssertGreaterThanOrEqual(port.openCount, 2, "recovery requires a fresh open")
        iface.stop()
    }

    func testTheRedialLoopSurvivesFailedAttempts() throws {
        let port = FlappableSerialPort()
        let iface = SerialInterface(name: "ser", port: "/dev/test", transport: port)
        iface.reconnectWait = 0.05
        try iface.start()
        port.failNextOpens = 2
        port.flap()

        let deadline = Date().addingTimeInterval(2.0)
        while !iface.isOnline && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertTrue(iface.isOnline,
                      "a failed redial attempt must not end the loop — Python retries forever")
        XCTAssertGreaterThanOrEqual(port.openCount, 3)
        iface.stop()
    }

    func testStopEndsTheRedialLoop() throws {
        let port = FlappableSerialPort()
        let iface = SerialInterface(name: "ser", port: "/dev/test", transport: port)
        iface.reconnectWait = 0.05
        try iface.start()
        port.failNextOpens = Int.max   // nothing to come back to
        port.flap()
        iface.stop()
        let settledCount = port.openCount
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(port.openCount, settledCount,
                       "stop() must cancel the redial loop, not leave a zombie dialer")
        XCTAssertFalse(iface.isOnline)
    }

    // MARK: - Failed writes are not traffic

    func testAFailedWriteIsNotCountedAsTransmittedBytes() throws {
        let port = FlappableSerialPort()
        let iface = SerialInterface(name: "ser", port: "/dev/test", transport: port)
        try iface.start()
        port.failWrites = true
        try? iface.send(makePacket())
        XCTAssertEqual(iface.txBytes, 0,
                       "a write that failed was counted as transmitted — rnstatus then shows "
                       + "growing TX counters on an interface whose device is gone, which is "
                       + "how the flap stayed invisible in bugs/034-adjacent reports")
        iface.stop()
    }

    // MARK: - RNode: recovery re-runs the whole bring-up

    private final class FlappableRNodeTransport: RNodeTransport {
        var byteHandler: ((Data) -> Void)?
        var onTransportError: ((Error) -> Void)?
        private(set) var openCount = 0
        private(set) var detectResponses = 0
        weak var echoSource: RNodeInterface?

        func open() throws { openCount += 1 }
        func close() {}
        func write(_ data: Data) throws {
            let bytes = [UInt8](data)
            guard bytes.count > 1, bytes[1] == KISS.cmdDetect, let iface = echoSource
            else { return }
            detectResponses += 1
            var reply = Data([KISS.fend, KISS.cmdDetect, KISS.detectResp, KISS.fend])
            func frame(_ cmd: UInt8, _ payload: [UInt8]) {
                reply.append(KISS.fend); reply.append(cmd)
                reply.append(contentsOf: payload); reply.append(KISS.fend)
            }
            func be32(_ v: UInt32) -> [UInt8] {
                [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF),
                 UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
            }
            frame(KISS.cmdFrequency, be32(iface.frequency))
            frame(KISS.cmdBandwidth, be32(iface.bandwidth))
            frame(KISS.cmdTxpower, [UInt8(clamping: iface.txPower)])
            frame(KISS.cmdSf, [UInt8(clamping: iface.sf)])
            frame(KISS.cmdCr, [UInt8(clamping: iface.cr)])
            frame(KISS.cmdRadioState, [KISS.radioStateOn])
            byteHandler?(reply)
        }
        func flap() { onTransportError?(DeviceGone()) }
    }

    func testAnRNodeRedialsAndReconfiguresAfterLoss() throws {
        let transport = FlappableRNodeTransport()
        let iface = RNodeInterface(name: "lora", transport: transport)
        iface.frequency = 869_525_000; iface.bandwidth = 125_000
        iface.txPower = 7; iface.sf = 8; iface.cr = 5
        iface.reconnectWaitOverride = 0.05
        transport.echoSource = iface
        try iface.start()
        XCTAssertTrue(iface.waitUntilOnline(timeout: 3.0))
        XCTAssertEqual(transport.detectResponses, 1)

        transport.flap()
        XCTAssertFalse(iface.isOnline, "loss must take the radio offline immediately")

        let deadline = Date().addingTimeInterval(2.0)
        while !iface.isOnline && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertTrue(iface.isOnline, "the RNode never came back — RNodeInterface.py:1155-1187")
        XCTAssertGreaterThanOrEqual(transport.detectResponses, 2,
                                    "recovery must re-run the whole bring-up gate (detect + "
                                    + "initRadio + validate), not merely reopen the port — the "
                                    + "modem lost its configuration with its power")
        iface.stop()
    }

    // MARK: - The POSIX layer actually reports loss

    #if os(macOS)
    /// The linchpin: `POSIXSerialPort` discarded device-gone reads (`guard count > 0 else
    /// { return }`), so nothing above it could ever notice a flap. A pty pair gives a real
    /// tty whose master side can vanish.
    func testPOSIXSerialPortSurfacesDeviceLoss() throws {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        try XCTSkipIf(master < 0, "no pty available")
        grantpt(master); unlockpt(master)
        guard let slavePath = ptsname(master).map({ String(cString: $0) }) else {
            close(master); throw XCTSkip("could not resolve pty slave path")
        }

        let port = POSIXSerialPort()
        let lost = expectation(description: "device loss surfaced")
        port.onTransportError = { _ in lost.fulfill() }
        try port.open(port: slavePath, baudRate: 9600, dataBits: 8, parity: .none, stopBits: 1)

        close(master)   // the "device" disappears
        wait(for: [lost], timeout: 3.0)
        XCTAssertFalse(port.isOpen, "a lost device must leave the port closed, ready to redial")
    }
    #endif
}
