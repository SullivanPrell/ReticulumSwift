import XCTest
@testable import ReticulumSwift

/// Python gates `online` on the full bring-up chain: `configure_device` sends detect, waits
/// (bounded), and on no answer closes the port and stays offline (`RNodeInterface.py:432-448`);
/// on detect it runs `initRadio()` then `validateRadioState()`, and only then sets
/// `interface_ready = True` / `online = True` (`:457-462`) — a parameter mismatch aborts
/// startup and closes the port (`:463-467`). The port's `start()` was `open(); isOnline = true`
/// with `detect`/`initRadio`/`validateRadioState` production-dead (zero call sites): a
/// host-mode RNode never received CMD_FREQUENCY/…/CMD_RADIO_STATE ON, so its radio stayed off
/// while `rnstatus` reported the interface Up. These tests drive `start()` end to end against
/// mock transports — the existing tests called the helpers by hand, which is exactly how the
/// dead path hid behind green.
final class RNodeOnlineGateTests: XCTestCase {

    /// Answers a detect write with a detect response plus echoes of every radio parameter —
    /// what real firmware does as each `set*` command lands. Echo values are configurable so a
    /// mismatch can be staged; defaults echo whatever the interface was configured with.
    private final class EchoingRNodeTransport: RNodeTransport {
        var byteHandler: ((Data) -> Void)?
        private(set) var opened = false
        private(set) var closed = false
        private(set) var writes: [Data] = []

        /// The interface whose configured values to echo. Set after interface construction.
        weak var echoSource: RNodeInterface?
        /// Override the echoed bandwidth to stage a mismatch.
        var bandwidthOverride: UInt32?

        func open() throws { opened = true }
        func close() { closed = true }

        func write(_ data: Data) throws {
            writes.append(data)
            let bytes = [UInt8](data)
            guard bytes.count > 1, bytes[1] == KISS.cmdDetect, let iface = echoSource
            else { return }
            // Values below are chosen free of FEND/FESC bytes, so raw frames suffice.
            var reply = Data([KISS.fend, KISS.cmdDetect, KISS.detectResp, KISS.fend])
            func frame(_ cmd: UInt8, _ payload: [UInt8]) {
                reply.append(KISS.fend); reply.append(cmd)
                reply.append(contentsOf: payload); reply.append(KISS.fend)
            }
            func be32(_ v: UInt32) -> [UInt8] {
                [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
            }
            frame(KISS.cmdFrequency, be32(iface.frequency))
            frame(KISS.cmdBandwidth, be32(bandwidthOverride ?? iface.bandwidth))
            frame(KISS.cmdTxpower, [UInt8(clamping: iface.txPower)])
            frame(KISS.cmdSf, [UInt8(clamping: iface.sf)])
            frame(KISS.cmdCr, [UInt8(clamping: iface.cr)])
            frame(KISS.cmdRadioState, [KISS.radioStateOn])
            byteHandler?(reply)
        }
    }

    /// Accepts everything, answers nothing — an absent or dead device.
    private final class SilentRNodeTransport: RNodeTransport {
        var byteHandler: ((Data) -> Void)?
        private(set) var closed = false
        private(set) var writes: [Data] = []
        func open() throws {}
        func close() { closed = true }
        func write(_ data: Data) throws { writes.append(data) }
    }

    private func configuredInterface(transport: RNodeTransport) -> RNodeInterface {
        let iface = RNodeInterface(name: "Bench LoRa", transport: transport)
        iface.frequency = 869_525_000
        iface.bandwidth = 125_000
        iface.txPower = 7
        iface.sf = 8
        iface.cr = 5
        return iface
    }

    func testAnAnsweringDeviceComesOnlineConfigured() throws {
        let transport = EchoingRNodeTransport()
        let iface = configuredInterface(transport: transport)
        transport.echoSource = iface
        try iface.start()

        XCTAssertTrue(iface.detected, "the detect response must be consumed during start()")
        XCTAssertTrue(iface.isOnline)
        XCTAssertTrue(iface.interfaceReady,
                      "Python sets interface_ready only on a validated bring-up "
                      + "(RNodeInterface.py:459)")
        // The radio must actually have been configured and turned on — the defect was a
        // healthy-looking interface whose modem never received a single command.
        let allWrites = transport.writes.reduce(Data(), +)
        for (cmd, label) in [(KISS.cmdFrequency, "frequency"), (KISS.cmdBandwidth, "bandwidth"),
                             (KISS.cmdTxpower, "txpower"), (KISS.cmdSf, "spreadingfactor"),
                             (KISS.cmdCr, "codingrate"), (KISS.cmdRadioState, "radio state")] {
            XCTAssertTrue(allWrites.contains(cmd),
                          "start() never sent \(label) — initRadio() is not in the start path "
                          + "(Python configure_device → initRadio, RNodeInterface.py:457)")
        }
    }

    func testASilentDeviceLeavesTheInterfaceOfflineAndClosed() throws {
        let transport = SilentRNodeTransport()
        let iface = configuredInterface(transport: transport)
        iface.detectTimeout = 0.05
        try iface.start()

        XCTAssertFalse(iface.isOnline,
                       """
                       start() reported online with no device answering — Python closes the \
                       port and stays offline ("Could not detect device", \
                       RNodeInterface.py:445-448); an online interface with a dead modem \
                       silently blackholes every packet Transport routes to it
                       """)
        XCTAssertTrue(transport.closed, "Python closes the serial port on a failed detect")
    }

    func testAParameterMismatchAbortsStartup() throws {
        let transport = EchoingRNodeTransport()
        let iface = configuredInterface(transport: transport)
        transport.echoSource = iface
        transport.bandwidthOverride = 250_000   // hardware reports a bandwidth we did not set
        iface.validateTimeout = 0.1
        try iface.start()

        XCTAssertFalse(iface.isOnline,
                       "Python aborts startup when the reported radio parameters do not match "
                       + "the configuration (\"Aborting RNode startup\", "
                       + "RNodeInterface.py:463-467)")
        XCTAssertTrue(transport.closed)
    }

    /// Python None-guards only the frequency comparison; bandwidth, txpower, sf and state
    /// compare unconditionally, so a device that echoed *nothing* is a mismatch
    /// (`RNodeInterface.py:670-685`). The port guarded every comparison with `if let`, which
    /// made validation vacuously true against total silence.
    func testValidationFailsWhenNothingWasEchoed() {
        let iface = configuredInterface(transport: SilentRNodeTransport())
        XCTAssertFalse(iface.validateRadioState(),
                       "an unanswered configuration validated as correct — every comparison "
                       + "was nil-guarded, so total silence passed (Python fails on "
                       + "bandwidth None != configured, RNodeInterface.py:674-676)")
    }

    // MARK: - RNodeMultiInterface, same gate

    private final class EchoingMultiTransport: RNodeTransport {
        var byteHandler: ((Data) -> Void)?
        private(set) var closed = false
        private(set) var writes: [Data] = []
        func open() throws {}
        func close() { closed = true }
        func write(_ data: Data) throws {
            writes.append(data)
            let bytes = [UInt8](data)
            guard bytes.count > 1, bytes[1] == KISS.cmdDetect else { return }
            byteHandler?(Data([KISS.fend, KISS.cmdDetect, KISS.detectResp, KISS.fend]))
        }
    }

    func testAMultiInterfaceGatesOnDetectAndConfiguresItsRadios() throws {
        let transport = EchoingMultiTransport()
        let sub = RNodeSubInterface(name: "High", index: 0, interfaceType: "SX1262",
                                    frequency: 869_525_000, bandwidth: 125_000,
                                    txPower: 7, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "Dual", transport: transport,
                                            subInterfaces: [sub])
        try multi.start()
        XCTAssertTrue(multi.isOnline)
        let allWrites = transport.writes.reduce(Data(), +)
        XCTAssertTrue(allWrites.contains(KISS.cmdSelInt),
                      "start() never configured any sub-interface — initAllRadios() is not in "
                      + "the start path (Python detect → CMD_INTERFACES → init radios)")
    }

    func testASilentMultiDeviceStaysOffline() throws {
        let transport = SilentRNodeTransport()
        let sub = RNodeSubInterface(name: "High", index: 0, interfaceType: "SX1262",
                                    frequency: 869_525_000, bandwidth: 125_000,
                                    txPower: 7, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "Dual", transport: transport,
                                            subInterfaces: [sub])
        multi.detectTimeout = 0.05
        try multi.start()
        XCTAssertFalse(multi.isOnline,
                       "the multi interface has the identical gate defect: open(); online = true "
                       + "with detect/initAllRadios production-dead")
    }
}
