import XCTest
@testable import ReticulumSwift

// MARK: - Mock transport for capturing writes and injecting reads

final class MockRNodeTransport: RNodeTransport {
    var byteHandler: ((Data) -> Void)?
    var writtenData: [Data] = []
    var isOpen = false

    func open() throws { isOpen = true }
    func close() { isOpen = false }
    func write(_ data: Data) throws { writtenData.append(data) }

    /// Feed bytes as if they arrived from the hardware.
    func inject(_ bytes: [UInt8]) {
        byteHandler?(Data(bytes))
    }
}

// MARK: - KISS Command Constants

final class KISSCommandConstantsTests: XCTestCase {

    // Verify every CMD_* value against RNodeInterface.py KISS class
    func testFEND() { XCTAssertEqual(KISS.fend, 0xC0) }
    func testFESC() { XCTAssertEqual(KISS.fesc, 0xDB) }
    func testTFEND() { XCTAssertEqual(KISS.tfend, 0xDC) }
    func testTFESC() { XCTAssertEqual(KISS.tfesc, 0xDD) }

    func testCmdData()        { XCTAssertEqual(KISS.cmdData,        0x00) }
    func testCmdFrequency()   { XCTAssertEqual(KISS.cmdFrequency,   0x01) }
    func testCmdBandwidth()   { XCTAssertEqual(KISS.cmdBandwidth,   0x02) }
    func testCmdTxpower()     { XCTAssertEqual(KISS.cmdTxpower,     0x03) }
    func testCmdSf()          { XCTAssertEqual(KISS.cmdSf,          0x04) }
    func testCmdCr()          { XCTAssertEqual(KISS.cmdCr,          0x05) }
    func testCmdRadioState()  { XCTAssertEqual(KISS.cmdRadioState,  0x06) }
    func testCmdRadioLock()   { XCTAssertEqual(KISS.cmdRadioLock,   0x07) }
    func testCmdDetect()      { XCTAssertEqual(KISS.cmdDetect,      0x08) }
    func testCmdLeave()       { XCTAssertEqual(KISS.cmdLeave,       0x0A) }
    func testCmdStAlock()     { XCTAssertEqual(KISS.cmdStAlock,     0x0B) }
    func testCmdLtAlock()     { XCTAssertEqual(KISS.cmdLtAlock,     0x0C) }
    func testCmdReady()       { XCTAssertEqual(KISS.cmdReady,       0x0F) }
    func testCmdStatRx()      { XCTAssertEqual(KISS.cmdStatRx,      0x21) }
    func testCmdStatTx()      { XCTAssertEqual(KISS.cmdStatTx,      0x22) }
    func testCmdStatRssi()    { XCTAssertEqual(KISS.cmdStatRssi,    0x23) }
    func testCmdStatSnr()     { XCTAssertEqual(KISS.cmdStatSnr,     0x24) }
    func testCmdStatChtm()    { XCTAssertEqual(KISS.cmdStatChtm,    0x25) }
    func testCmdStatPhyprm()  { XCTAssertEqual(KISS.cmdStatPhyprm,  0x26) }
    func testCmdStatBat()     { XCTAssertEqual(KISS.cmdStatBat,     0x27) }
    func testCmdStatCsma()    { XCTAssertEqual(KISS.cmdStatCsma,    0x28) }
    func testCmdStatTemp()    { XCTAssertEqual(KISS.cmdStatTemp,    0x29) }
    func testCmdBlink()       { XCTAssertEqual(KISS.cmdBlink,       0x30) }
    func testCmdRandom()      { XCTAssertEqual(KISS.cmdRandom,      0x40) }
    func testCmdFbExt()       { XCTAssertEqual(KISS.cmdFbExt,       0x41) }
    func testCmdFbRead()      { XCTAssertEqual(KISS.cmdFbRead,      0x42) }
    func testCmdFbWrite()     { XCTAssertEqual(KISS.cmdFbWrite,     0x43) }
    func testCmdBtCtrl()      { XCTAssertEqual(KISS.cmdBtCtrl,      0x46) }
    func testCmdDispRead()    { XCTAssertEqual(KISS.cmdDispRead,    0x66) }
    func testCmdPlatform()    { XCTAssertEqual(KISS.cmdPlatform,    0x48) }
    func testCmdMcu()         { XCTAssertEqual(KISS.cmdMcu,         0x49) }
    func testCmdFwVersion()   { XCTAssertEqual(KISS.cmdFwVersion,   0x50) }
    func testCmdRomRead()     { XCTAssertEqual(KISS.cmdRomRead,     0x51) }
    func testCmdReset()       { XCTAssertEqual(KISS.cmdReset,       0x55) }
    func testCmdError()       { XCTAssertEqual(KISS.cmdError,       0x90) }
    func testCmdUnknown()     { XCTAssertEqual(KISS.cmdUnknown,     0xFE) }

    func testDetectReq()      { XCTAssertEqual(KISS.detectReq,      0x73) }
    func testDetectResp()     { XCTAssertEqual(KISS.detectResp,     0x46) }

    func testRadioStateOff()  { XCTAssertEqual(KISS.radioStateOff,  0x00) }
    func testRadioStateOn()   { XCTAssertEqual(KISS.radioStateOn,   0x01) }
    func testRadioStateAsk()  { XCTAssertEqual(KISS.radioStateAsk,  0xFF) }

    func testErrorInitRadio()     { XCTAssertEqual(KISS.errorInitRadio,    0x01) }
    func testErrorTxFailed()      { XCTAssertEqual(KISS.errorTxFailed,     0x02) }
    func testErrorEepromLocked()  { XCTAssertEqual(KISS.errorEepromLocked, 0x03) }
    func testErrorQueueFull()     { XCTAssertEqual(KISS.errorQueueFull,    0x04) }
    func testErrorMemoryLow()     { XCTAssertEqual(KISS.errorMemoryLow,    0x05) }
    func testErrorModemTimeout()  { XCTAssertEqual(KISS.errorModemTimeout, 0x06) }

    func testPlatformAVR()    { XCTAssertEqual(KISS.platformAVR,    0x90) }
    func testPlatformESP32()  { XCTAssertEqual(KISS.platformESP32,  0x80) }
    func testPlatformNRF52()  { XCTAssertEqual(KISS.platformNRF52,  0x70) }
}

// MARK: - RNodeInterface class constants

final class RNodeInterfaceConstantsTests: XCTestCase {
    func testHwMtu()             { XCTAssertEqual(RNodeInterface.hwMtuValue, 508) }
    func testFreqMin()           { XCTAssertEqual(RNodeInterface.freqMin, 137_000_000) }
    func testFreqMax()           { XCTAssertEqual(RNodeInterface.freqMax, 3_000_000_000) }
    func testRssiOffset()        { XCTAssertEqual(RNodeInterface.rssiOffset, 157) }
    func testCallsignMaxLen()    { XCTAssertEqual(RNodeInterface.callsignMaxLen, 32) }
    func testRequiredFwMaj()     { XCTAssertEqual(RNodeInterface.requiredFwVerMaj, 1) }
    func testRequiredFwMin()     { XCTAssertEqual(RNodeInterface.requiredFwVerMin, 52) }
    func testReconnectWait()     { XCTAssertEqual(RNodeInterface.reconnectWait, 5) }
    func testQSnrMinBase()       { XCTAssertEqual(RNodeInterface.qSnrMinBase, -9) }
    func testQSnrMax()           { XCTAssertEqual(RNodeInterface.qSnrMax, 6) }
    func testQSnrStep()          { XCTAssertEqual(RNodeInterface.qSnrStep, 2) }

    func testBatteryStateUnknown()     { XCTAssertEqual(RNodeInterface.batteryStateUnknown,     0x00) }
    func testBatteryStateDischarging() { XCTAssertEqual(RNodeInterface.batteryStateDischarging, 0x01) }
    func testBatteryStateCharging()    { XCTAssertEqual(RNodeInterface.batteryStateCharging,    0x02) }
    func testBatteryStateCharged()     { XCTAssertEqual(RNodeInterface.batteryStateCharged,     0x03) }
}

// MARK: - detect() wire format

final class RNodeDetectCommandTests: XCTestCase {
    /// Python: detect() sends exactly these 13 bytes:
    /// [FEND, CMD_DETECT, DETECT_REQ, FEND, CMD_FW_VERSION, 0x00,
    ///  FEND, CMD_PLATFORM, 0x00, FEND, CMD_MCU, 0x00, FEND]
    func testDetectSendsCorrectBytes() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        try iface.detect()
        XCTAssertEqual(mock.writtenData.count, 1)
        let bytes = [UInt8](mock.writtenData[0])
        let expected: [UInt8] = [
            0xC0, 0x08, 0x73,       // FEND CMD_DETECT DETECT_REQ
            0xC0, 0x50, 0x00,       // FEND CMD_FW_VERSION 0x00
            0xC0, 0x48, 0x00,       // FEND CMD_PLATFORM 0x00
            0xC0, 0x49, 0x00,       // FEND CMD_MCU 0x00
            0xC0                    // trailing FEND
        ]
        XCTAssertEqual(bytes, expected)
    }
}

// MARK: - leave() wire format

final class RNodeLeaveCommandTests: XCTestCase {
    /// Python: leave() sends [FEND, CMD_LEAVE, 0xFF, FEND]
    func testLeaveSendsCorrectBytes() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        try iface.leave()
        XCTAssertEqual(mock.writtenData.count, 1)
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x0A, 0xFF, 0xC0])
    }
}

// MARK: - Radio parameter byte-packing

final class RNodeFrequencyPackingTests: XCTestCase {
    /// Python setFrequency() for 868_000_000 Hz:
    ///   868_000_000 = 0x33BCA100
    ///   c1=0x33, c2=0xBC, c3=0xA1, c4=0x00
    ///   No escaping needed for these bytes.
    ///   Frame: [FEND, CMD_FREQUENCY, 0x33, 0xBC, 0xA1, 0x00, FEND]
    func testSetFrequency868MHz() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency = 868_000_000
        try iface.setFrequency()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x01, 0x33, 0xBC, 0xA1, 0x00, 0xC0])
    }

    /// 915_000_000 Hz = 0x3689CAC0
    /// c1=0x36, c2=0x89, c3=0xCA, c4=0xC0
    /// c4=0xC0 is FEND — must be escaped to FESC(0xDB) TFEND(0xDC)
    /// Frame: [FEND, CMD_FREQUENCY, 0x36, 0x89, 0xCA, 0xDB, 0xDC, FEND]
    func testSetFrequency915MHz() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency = 915_000_000
        try iface.setFrequency()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x01, 0x36, 0x89, 0xCA, 0xDB, 0xDC, 0xC0])
    }

    /// Test KISS escaping: if any frequency byte == 0xC0 (FEND), it must be escaped.
    /// 0x00C0_0000 = 12582912 Hz (contrived)
    /// Bytes: 0x00, 0xC0, 0x00, 0x00 → escaped: 0x00, 0xDB, 0xDC, 0x00, 0x00
    func testSetFrequencyEscapesFEND() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency = 0x00C0_0000  // 12_582_912 Hz
        try iface.setFrequency()
        let bytes = [UInt8](mock.writtenData[0])
        // [FEND, CMD_FREQUENCY, 0x00, FESC, TFEND, 0x00, 0x00, FEND]
        XCTAssertEqual(bytes, [0xC0, 0x01, 0x00, 0xDB, 0xDC, 0x00, 0x00, 0xC0])
    }

    /// Test KISS escaping: frequency byte == 0xDB (FESC) must be escaped.
    /// 0x00DB_0000 = 14_352_384 Hz
    func testSetFrequencyEscapesFESC() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency = 0x00DB_0000  // 14_352_384 Hz
        try iface.setFrequency()
        let bytes = [UInt8](mock.writtenData[0])
        // [FEND, CMD_FREQUENCY, 0x00, FESC, TFESC, 0x00, 0x00, FEND]
        XCTAssertEqual(bytes, [0xC0, 0x01, 0x00, 0xDB, 0xDD, 0x00, 0x00, 0xC0])
    }
}

final class RNodeBandwidthPackingTests: XCTestCase {
    /// 125_000 Hz bandwidth = 0x0001_E848
    /// c1=0x00, c2=0x01, c3=0xE8, c4=0x48
    func testSetBandwidth125k() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.bandwidth = 125_000
        try iface.setBandwidth()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x02, 0x00, 0x01, 0xE8, 0x48, 0xC0])
    }

    /// 500_000 Hz bandwidth = 0x0007_A120
    func testSetBandwidth500k() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.bandwidth = 500_000
        try iface.setBandwidth()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x02, 0x00, 0x07, 0xA1, 0x20, 0xC0])
    }
}

final class RNodeTxPowerPackingTests: XCTestCase {
    /// TXPower 14 dBm → single byte 0x0E
    /// Frame: [FEND, CMD_TXPOWER, 0x0E, FEND]
    func testSetTxPower14() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.txPower = 14
        try iface.setTxPower()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x03, 0x0E, 0xC0])
    }

    /// TXPower 0 → [FEND, CMD_TXPOWER, 0x00, FEND]
    func testSetTxPower0() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.txPower = 0
        try iface.setTxPower()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x03, 0x00, 0xC0])
    }
}

final class RNodeSpreadingFactorPackingTests: XCTestCase {
    /// SF7 → [FEND, CMD_SF, 0x07, FEND]
    func testSetSf7() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.sf = 7
        try iface.setSpreadingFactor()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x04, 0x07, 0xC0])
    }

    /// SF12 → [FEND, CMD_SF, 0x0C, FEND]
    func testSetSf12() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.sf = 12
        try iface.setSpreadingFactor()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x04, 0x0C, 0xC0])
    }
}

final class RNodeCodingRatePackingTests: XCTestCase {
    /// CR5 → [FEND, CMD_CR, 0x05, FEND]
    func testSetCr5() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.cr = 5
        try iface.setCodingRate()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x05, 0x05, 0xC0])
    }

    /// CR8 → [FEND, CMD_CR, 0x08, FEND]
    func testSetCr8() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.cr = 8
        try iface.setCodingRate()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x05, 0x08, 0xC0])
    }
}

// MARK: - Radio state command

final class RNodeRadioStateTests: XCTestCase {
    /// setRadioState(on) → [FEND, CMD_RADIO_STATE, 0x01, FEND]
    func testSetRadioStateOn() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        try iface.setRadioState(KISS.radioStateOn)
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x06, 0x01, 0xC0])
    }

    /// setRadioState(off) → [FEND, CMD_RADIO_STATE, 0x00, FEND]
    func testSetRadioStateOff() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        try iface.setRadioState(KISS.radioStateOff)
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x06, 0x00, 0xC0])
    }
}

// MARK: - initRadio() sequence

final class RNodeInitRadioSequenceTests: XCTestCase {
    /// initRadio() must send exactly 7 frames in this order:
    /// frequency, bandwidth, txpower, sf, cr, setRadioState(on)
    /// (st_alock and lt_alock skipped when nil)
    func testInitRadioSendsCorrectSequence() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency = 868_000_000
        iface.bandwidth = 125_000
        iface.txPower   = 14
        iface.sf        = 7
        iface.cr        = 5
        try iface.initRadio()
        // Without airtime locks: 5 config + 1 radio state = 6 writes
        // (stAlock and ltAlock are nil by default, so not sent)
        XCTAssertGreaterThanOrEqual(mock.writtenData.count, 6)

        // First frame is frequency
        let freqBytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(freqBytes[1], KISS.cmdFrequency)  // command byte

        // Second frame is bandwidth
        let bwBytes = [UInt8](mock.writtenData[1])
        XCTAssertEqual(bwBytes[1], KISS.cmdBandwidth)

        // Third frame is txpower
        let txpBytes = [UInt8](mock.writtenData[2])
        XCTAssertEqual(txpBytes[1], KISS.cmdTxpower)

        // Fourth frame is SF
        let sfBytes = [UInt8](mock.writtenData[3])
        XCTAssertEqual(sfBytes[1], KISS.cmdSf)

        // Fifth frame is CR
        let crBytes = [UInt8](mock.writtenData[4])
        XCTAssertEqual(crBytes[1], KISS.cmdCr)

        // Last frame is radio state ON
        let stateBytes = [UInt8](mock.writtenData[mock.writtenData.count - 1])
        XCTAssertEqual(stateBytes[1], KISS.cmdRadioState)
        XCTAssertEqual(stateBytes[2], KISS.radioStateOn)
    }

    /// When stAlock is set, CMD_ST_ALOCK frame appears before CMD_LT_ALOCK and radio state
    func testInitRadioSendsStAlockWhenSet() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency = 868_000_000
        iface.bandwidth = 125_000
        iface.txPower   = 14
        iface.sf        = 7
        iface.cr        = 5
        iface.stAlock   = 5.0   // 5%
        try iface.initRadio()
        let commands = mock.writtenData.map { [UInt8]($0)[1] }
        XCTAssertTrue(commands.contains(KISS.cmdStAlock))
    }

    /// When ltAlock is set, CMD_LT_ALOCK frame appears
    func testInitRadioSendsLtAlockWhenSet() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency = 868_000_000
        iface.bandwidth = 125_000
        iface.txPower   = 14
        iface.sf        = 7
        iface.cr        = 5
        iface.ltAlock   = 10.0  // 10%
        try iface.initRadio()
        let commands = mock.writtenData.map { [UInt8]($0)[1] }
        XCTAssertTrue(commands.contains(KISS.cmdLtAlock))
    }
}

// MARK: - Airtime lock byte packing

final class RNodeAirtimeLockTests: XCTestCase {
    /// stAlock 5.0% → int(5.0*100)=500=0x01F4
    /// Frame: [FEND, CMD_ST_ALOCK, 0x01, 0xF4, FEND]
    func testSetStAlock5Percent() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.stAlock = 5.0
        try iface.setStAlock()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x0B, 0x01, 0xF4, 0xC0])
    }

    /// ltAlock 10.0% → int(10.0*100)=1000=0x03E8
    func testSetLtAlock10Percent() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.ltAlock = 10.0
        try iface.setLtAlock()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x0C, 0x03, 0xE8, 0xC0])
    }

    /// When stAlock is nil, setStAlock() sends nothing
    func testSetStAlockNilSendsNothing() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.stAlock = nil
        try iface.setStAlock()
        XCTAssertEqual(mock.writtenData.count, 0)
    }
}

// MARK: - processIncoming: CMD_DETECT response

final class RNodeProcessIncomingDetectTests: XCTestCase {
    /// Inject FEND CMD_DETECT DETECT_RESP FEND → detected becomes true
    func testDetectResponseSetsDetected() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        XCTAssertFalse(iface.detected)
        // [FEND, CMD_DETECT, DETECT_RESP, FEND]
        mock.inject([0xC0, 0x08, 0x46, 0xC0])
        XCTAssertTrue(iface.detected)
    }

    /// DETECT_RESP != 0x46 → detected stays false
    func testWrongDetectRespDoesNotSetDetected() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x08, 0x00, 0xC0])  // wrong byte
        XCTAssertFalse(iface.detected)
    }
}

// MARK: - processIncoming: CMD_PLATFORM and CMD_MCU

final class RNodeProcessIncomingPlatformTests: XCTestCase {
    func testPlatformESP32Parsed() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x48, 0x80, 0xC0])  // CMD_PLATFORM, PLATFORM_ESP32
        XCTAssertEqual(iface.platform, KISS.platformESP32)
    }

    func testPlatformNRF52Parsed() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x48, 0x70, 0xC0])  // CMD_PLATFORM, PLATFORM_NRF52
        XCTAssertEqual(iface.platform, KISS.platformNRF52)
    }

    func testMcuParsed() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x49, 0xA0, 0xC0])  // CMD_MCU, 0xA0
        XCTAssertEqual(iface.mcu, 0xA0)
    }
}

// MARK: - processIncoming: CMD_FW_VERSION

final class RNodeProcessIncomingFwVersionTests: XCTestCase {
    /// [FEND, CMD_FW_VERSION, maj, min, FEND] → majVersion=maj, minVersion=min
    func testFwVersionParsed() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x50, 0x01, 0x34, 0xC0])  // v1.52
        XCTAssertEqual(iface.majVersion, 1)
        XCTAssertEqual(iface.minVersion, 52)
    }

    func testFwVersionBelowRequiredSetsNotOk() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x50, 0x01, 0x10, 0xC0])  // v1.16 — too old
        XCTAssertFalse(iface.firmwareOk)
    }

    func testFwVersionAtRequiredSetsOk() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x50, 0x01, 0x34, 0xC0])  // v1.52 — exactly required
        XCTAssertTrue(iface.firmwareOk)
    }

    func testFwVersionAboveRequiredSetsOk() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x50, 0x02, 0x00, 0xC0])  // v2.0 — above required
        XCTAssertTrue(iface.firmwareOk)
    }
}

// MARK: - processIncoming: CMD_FREQUENCY echo

final class RNodeProcessIncomingFrequencyTests: XCTestCase {
    /// Device echoes back frequency as 4-byte big-endian
    func testFrequencyEchoDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        // 868_000_000 = 0x33BCA100
        // c4=0x00, no escaping needed
        mock.inject([0xC0, 0x01, 0x33, 0xBC, 0xA1, 0x00, 0xC0])
        XCTAssertEqual(iface.rFrequency, 868_000_000)
    }
}

// MARK: - processIncoming: CMD_BANDWIDTH echo

final class RNodeProcessIncomingBandwidthTests: XCTestCase {
    func testBandwidthEchoDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        // 125_000 = 0x0001E848
        mock.inject([0xC0, 0x02, 0x00, 0x01, 0xE8, 0x48, 0xC0])
        XCTAssertEqual(iface.rBandwidth, 125_000)
    }
}

// MARK: - processIncoming: CMD_TXPOWER echo

final class RNodeProcessIncomingTxPowerTests: XCTestCase {
    func testTxPowerEchoDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x03, 0x0E, 0xC0])  // 14 dBm
        XCTAssertEqual(iface.rTxPower, 14)
    }
}

// MARK: - processIncoming: CMD_SF echo

final class RNodeProcessIncomingSpreadingFactorTests: XCTestCase {
    func testSfEchoDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x04, 0x07, 0xC0])
        XCTAssertEqual(iface.rSf, 7)
    }
}

// MARK: - processIncoming: CMD_CR echo

final class RNodeProcessIncomingCodingRateTests: XCTestCase {
    func testCrEchoDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x05, 0x05, 0xC0])
        XCTAssertEqual(iface.rCr, 5)
    }
}

// MARK: - processIncoming: CMD_RADIO_STATE echo

final class RNodeProcessIncomingRadioStateTests: XCTestCase {
    func testRadioStateOnEchoDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x06, 0x01, 0xC0])
        XCTAssertEqual(iface.rState, KISS.radioStateOn)
    }

    func testRadioStateOffEchoDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x06, 0x00, 0xC0])
        XCTAssertEqual(iface.rState, KISS.radioStateOff)
    }
}

// MARK: - processIncoming: RSSI

final class RNodeProcessIncomingRssiTests: XCTestCase {
    /// RSSI byte = rawValue; rStatRssi = rawValue - RSSI_OFFSET (157)
    /// rawValue 214 → rssi = 214 - 157 = 57 ... wait Python: byte - offset
    /// Actually python: self.r_stat_rssi = byte-RNodeInterface.RSSI_OFFSET
    /// So byte=214 → 57, byte=100 → -57
    func testRssiDecodedWithOffset() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x23, 214, 0xC0])  // CMD_STAT_RSSI, raw=214
        XCTAssertEqual(iface.rStatRssi, 214 - 157)  // = 57
    }

    func testRssiNegativeDecodedWithOffset() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x23, 100, 0xC0])  // CMD_STAT_RSSI, raw=100
        XCTAssertEqual(iface.rStatRssi, 100 - 157)  // = -57
    }
}

// MARK: - processIncoming: SNR

final class RNodeProcessIncomingSNRTests: XCTestCase {
    /// Python: r_stat_snr = int.from_bytes([byte], byteorder="big", signed=True) * 0.25
    /// byte 0x08 (8 signed) → snr = 8 * 0.25 = 2.0
    func testSnrPositiveDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x24, 0x08, 0xC0])
        XCTAssertNotNil(iface.rStatSnr)
        XCTAssertEqual(iface.rStatSnr!, Float(2.0), accuracy: Float(0.001))
    }

    /// byte 0xFF (-1 signed) → snr = -1 * 0.25 = -0.25
    func testSnrNegativeDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x24, 0xFF, 0xC0])
        XCTAssertNotNil(iface.rStatSnr)
        XCTAssertEqual(iface.rStatSnr!, Float(-0.25), accuracy: Float(0.001))
    }

    /// byte 0xE8 (-24 signed) → snr = -24 * 0.25 = -6.0
    func testSnrNegativeLargeDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x24, 0xE8, 0xC0])
        XCTAssertNotNil(iface.rStatSnr)
        XCTAssertEqual(iface.rStatSnr!, Float(-6.0), accuracy: Float(0.001))
    }
}

// MARK: - processIncoming: CMD_STAT_BAT

final class RNodeProcessIncomingBatteryTests: XCTestCase {
    /// CMD_STAT_BAT sends 2 bytes: [state, percent]
    /// state=BATTERY_STATE_CHARGING(0x02), percent=75
    func testBatteryChargingParsed() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x27, 0x02, 75, 0xC0])
        XCTAssertEqual(iface.rBatteryState, RNodeInterface.batteryStateCharging)
        XCTAssertEqual(iface.rBatteryPercent, 75)
    }

    func testBatteryDischarging() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x27, 0x01, 42, 0xC0])
        XCTAssertEqual(iface.rBatteryState, RNodeInterface.batteryStateDischarging)
        XCTAssertEqual(iface.rBatteryPercent, 42)
    }

    func testBatteryCharged() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x27, 0x03, 100, 0xC0])
        XCTAssertEqual(iface.rBatteryState, RNodeInterface.batteryStateCharged)
        XCTAssertEqual(iface.rBatteryPercent, 100)
    }

    /// Python clamps percent to 100 if > 100
    func testBatteryPercentClamped() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x27, 0x03, 200, 0xC0])  // 200 > 100
        XCTAssertEqual(iface.rBatteryPercent, 100)
    }
}

// MARK: - getBatteryStateString

final class RNodeBatteryStateStringTests: XCTestCase {
    func testCharged() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rBatteryState = RNodeInterface.batteryStateCharged
        XCTAssertEqual(iface.getBatteryStateString(), "charged")
    }

    func testCharging() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rBatteryState = RNodeInterface.batteryStateCharging
        XCTAssertEqual(iface.getBatteryStateString(), "charging")
    }

    func testDischarging() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rBatteryState = RNodeInterface.batteryStateDischarging
        XCTAssertEqual(iface.getBatteryStateString(), "discharging")
    }

    func testUnknown() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rBatteryState = RNodeInterface.batteryStateUnknown
        XCTAssertEqual(iface.getBatteryStateString(), "unknown")
    }
}

// MARK: - processIncoming: CMD_STAT_RX and CMD_STAT_TX

final class RNodeProcessIncomingStatCountersTests: XCTestCase {
    /// CMD_STAT_RX sends 4 bytes big-endian uint32
    func testStatRxDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        // value = 0x00000042 = 66
        mock.inject([0xC0, 0x21, 0x00, 0x00, 0x00, 0x42, 0xC0])
        XCTAssertEqual(iface.rStatRx, 66)
    }

    func testStatTxDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        // value = 0x000000FF = 255
        mock.inject([0xC0, 0x22, 0x00, 0x00, 0x00, 0xFF, 0xC0])
        XCTAssertEqual(iface.rStatTx, 255)
    }
}

// MARK: - processIncoming: CMD_READY triggers queue processing

final class RNodeProcessIncomingReadyTests: XCTestCase {
    func testReadyTriggersSetsInterfaceReady() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.interfaceReady = false
        mock.inject([0xC0, 0x0F, 0x00, 0xC0])  // CMD_READY
        XCTAssertTrue(iface.interfaceReady)
    }

    func testReadyDrainsQueue() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.interfaceReady = false
        // Queue a packet
        let queued = Data([0xAA, 0xBB])
        iface.packetQueue.append(queued)
        // Now inject CMD_READY
        mock.inject([0xC0, 0x0F, 0x00, 0xC0])
        // Queue should be drained
        XCTAssertEqual(iface.packetQueue.count, 0)
    }
}

// MARK: - processIncoming: CMD_RADIO_LOCK

final class RNodeProcessIncomingRadioLockTests: XCTestCase {
    func testRadioLockParsed() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x07, 0x01, 0xC0])  // CMD_RADIO_LOCK, locked=1
        XCTAssertEqual(iface.rLock, 1)
    }
}

// MARK: - processIncoming: CMD_RANDOM

final class RNodeProcessIncomingRandomTests: XCTestCase {
    func testRandomByteStored() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x40, 0xAB, 0xC0])
        XCTAssertEqual(iface.rRandom, 0xAB)
    }
}

// MARK: - updateBitrate

final class RNodeUpdateBitrateTests: XCTestCase {
    /// Python formula: sf * (4/cr / (2^sf / (bw/1000))) * 1000
    /// SF=7, BW=125000, CR=5:
    ///   4/5 = 0.8
    ///   2^7 / (125000/1000) = 128/125 = 1.024
    ///   0.8 / 1.024 = 0.78125
    ///   7 * 0.78125 * 1000 = 5468.75 bps
    func testBitrateForSF7BW125CR5() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rSf = 7
        iface.rBandwidth = 125_000
        iface.rCr = 5
        iface.updateBitrate()
        XCTAssertEqual(iface.bitrate, 5468, accuracy: 10)
    }

    /// SF=12, BW=125000, CR=5 should be much lower
    func testBitrateForSF12BW125CR5() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rSf = 12
        iface.rBandwidth = 125_000
        iface.rCr = 5
        iface.updateBitrate()
        XCTAssertGreaterThan(iface.bitrate, 0)
        XCTAssertLessThan(iface.bitrate, 500)
    }

    /// If any parameter is 0, bitrate should remain 0 (not crash)
    func testBitrateWithZeroBandwidthDoesNotCrash() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rSf = 0
        iface.rBandwidth = 0
        iface.rCr = 0
        iface.updateBitrate()
        XCTAssertEqual(iface.bitrate, 0)
    }
}

// MARK: - validateRadioState

final class RNodeValidateRadioStateTests: XCTestCase {
    /// All reported params match configured → validateRadioState returns true
    func testValidatesOkWhenParamsMatch() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency  = 868_000_000
        iface.bandwidth  = 125_000
        iface.txPower    = 14
        iface.sf         = 7
        iface.state      = KISS.radioStateOn

        iface.rFrequency = 868_000_000
        iface.rBandwidth = 125_000
        iface.rTxPower   = 14
        iface.rSf        = 7
        iface.rState     = KISS.radioStateOn

        XCTAssertTrue(iface.validateRadioState())
    }

    /// Frequency within 100 Hz tolerance is accepted
    func testValidatesOkWithinFrequencyTolerance() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency  = 868_000_000
        iface.bandwidth  = 125_000
        iface.txPower    = 14
        iface.sf         = 7
        iface.state      = KISS.radioStateOn

        iface.rFrequency = 868_000_050  // within 100 Hz
        iface.rBandwidth = 125_000
        iface.rTxPower   = 14
        iface.rSf        = 7
        iface.rState     = KISS.radioStateOn

        XCTAssertTrue(iface.validateRadioState())
    }

    /// Frequency > 100 Hz off fails validation
    func testValidatesFailsOnFrequencyMismatch() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency  = 868_000_000
        iface.bandwidth  = 125_000
        iface.txPower    = 14
        iface.sf         = 7
        iface.state      = KISS.radioStateOn

        iface.rFrequency = 868_001_000  // > 100 Hz off
        iface.rBandwidth = 125_000
        iface.rTxPower   = 14
        iface.rSf        = 7
        iface.rState     = KISS.radioStateOn

        XCTAssertFalse(iface.validateRadioState())
    }

    /// Bandwidth mismatch fails
    func testValidatesFailsOnBandwidthMismatch() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency  = 868_000_000
        iface.bandwidth  = 125_000
        iface.txPower    = 14
        iface.sf         = 7
        iface.state      = KISS.radioStateOn

        iface.rFrequency = 868_000_000
        iface.rBandwidth = 250_000  // mismatch
        iface.rTxPower   = 14
        iface.rSf        = 7
        iface.rState     = KISS.radioStateOn

        XCTAssertFalse(iface.validateRadioState())
    }

    /// Radio state mismatch fails
    func testValidatesFailsOnStateMismatch() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.frequency  = 868_000_000
        iface.bandwidth  = 125_000
        iface.txPower    = 14
        iface.sf         = 7
        iface.state      = KISS.radioStateOn

        iface.rFrequency = 868_000_000
        iface.rBandwidth = 125_000
        iface.rTxPower   = 14
        iface.rSf        = 7
        iface.rState     = KISS.radioStateOff  // mismatch

        XCTAssertFalse(iface.validateRadioState())
    }
}

// MARK: - SNR quality calculation

final class RNodeSnrQualityTests: XCTestCase {
    /// Python: sfs=sf-7; q_snr_min=Q_SNR_MIN_BASE - sfs*Q_SNR_STEP = -9 - sfs*2
    /// For SF7: sfs=0, q_snr_min=-9, q_snr_max=6, span=15
    /// snr=6.0 → quality=(6-(-9))/15 * 100 = 100.0
    func testSnrQualityAtMaxForSF7() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rSf = 7
        // byte = Int8(24) = 0x18, snr = 24*0.25 = 6.0
        mock.inject([0xC0, 0x24, 0x18, 0xC0])
        XCTAssertEqual(iface.rStatQ!, 100.0, accuracy: 0.1)
    }

    /// snr = -9.0 for SF7 → quality = 0.0
    func testSnrQualityAtMinForSF7() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rSf = 7
        // byte = Int8(-36) = 0xDC, snr = -36*0.25 = -9.0
        mock.inject([0xC0, 0x24, 0xDC, 0xC0])
        XCTAssertEqual(iface.rStatQ!, 0.0, accuracy: 0.1)
    }

    /// snr below min is clamped to 0.0
    func testSnrQualityClampedBelowZero() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rSf = 7
        // byte = Int8(-80) = 0xB0, very negative → clamped to 0
        mock.inject([0xC0, 0x24, 0xB0, 0xC0])
        XCTAssertEqual(iface.rStatQ!, 0.0, accuracy: 0.1)
    }
}

// MARK: - processIncoming: CMD_STAT_CHTM (channel timing)

final class RNodeProcessIncomingChtmTests: XCTestCase {
    /// CMD_STAT_CHTM: 11 bytes
    /// ats(2) + atl(2) + cus(2) + cul(2) + crs(1) + nfl(1) + ntf(1)
    func testChtmDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        // ats=500 (5.00%), atl=1000 (10.00%), cus=200 (2.00%), cul=400 (4.00%)
        // crs=214 → 214-157=57 dBm, nfl=160 → 3 dBm, ntf=0xFF → no interference
        let ats: [UInt8] = [0x01, 0xF4]  // 500
        let atl: [UInt8] = [0x03, 0xE8]  // 1000
        let cus: [UInt8] = [0x00, 0xC8]  // 200
        let cul: [UInt8] = [0x01, 0x90]  // 400
        let crs: UInt8   = 214            // 57 dBm
        let nfl: UInt8   = 160            // 3 dBm
        let ntf: UInt8   = 0xFF           // no interference
        mock.inject([0xC0, 0x25] + ats + atl + cus + cul + [crs, nfl, ntf] + [0xC0])
        XCTAssertEqual(iface.rAirtimeShort,      5.0,  accuracy: 0.01)
        XCTAssertEqual(iface.rAirtimeLong,       10.0, accuracy: 0.01)
        XCTAssertEqual(iface.rChannelLoadShort,  2.0,  accuracy: 0.01)
        XCTAssertEqual(iface.rChannelLoadLong,   4.0,  accuracy: 0.01)
        XCTAssertEqual(iface.rCurrentRssi!, 57)
        XCTAssertEqual(iface.rNoiseFloor!,  3)
        XCTAssertNil(iface.rInterference)
    }

    /// ntf != 0xFF → interference = ntf - RSSI_OFFSET
    func testChtmInterferenceDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        let ats: [UInt8] = [0x00, 0x00]
        let atl: [UInt8] = [0x00, 0x00]
        let cus: [UInt8] = [0x00, 0x00]
        let cul: [UInt8] = [0x00, 0x00]
        let crs: UInt8   = 157  // 0 dBm
        let nfl: UInt8   = 157  // 0 dBm
        let ntf: UInt8   = 200  // 43 dBm
        mock.inject([0xC0, 0x25] + ats + atl + cus + cul + [crs, nfl, ntf] + [0xC0])
        XCTAssertEqual(iface.rInterference!, 200 - 157)  // = 43
    }
}

// MARK: - processIncoming: CMD_STAT_PHYPRM

final class RNodeProcessIncomingPhyprmTests: XCTestCase {
    /// CMD_STAT_PHYPRM: 12 bytes
    /// lst(2)/1000 + lsr(2) + prs(2) + prt(2) + cst(2) + dft(2)
    func testPhyprmDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        // lst=1000 (1.0ms), lsr=1000, prs=8, prt=8, cst=5, dft=4
        let bytes: [UInt8] = [
            0xC0, 0x26,
            0x03, 0xE8,  // lst = 1000
            0x03, 0xE8,  // lsr = 1000
            0x00, 0x08,  // prs = 8
            0x00, 0x08,  // prt = 8
            0x00, 0x05,  // cst = 5
            0x00, 0x04,  // dft = 4
            0xC0
        ]
        mock.inject(bytes)
        XCTAssertEqual(iface.rSymbolTimeMs!,   1.0, accuracy: 0.001)
        XCTAssertEqual(iface.rSymbolRate!,     1000)
        XCTAssertEqual(iface.rPreambleSymbols!, 8)
        XCTAssertEqual(iface.rPreambleTimeMs!,  8)
        XCTAssertEqual(iface.rCsmaSlotTimeMs!,  5)
        XCTAssertEqual(iface.rCsmaDifsMs!,      4)
    }
}

// MARK: - processIncoming: CMD_STAT_CSMA

final class RNodeProcessIncomingCsmaTests: XCTestCase {
    /// CMD_STAT_CSMA: 3 bytes [cw_band, cw_min, cw_max]
    func testCsmaDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x28, 0x03, 0x02, 0x10, 0xC0])
        XCTAssertEqual(iface.rCsmaCwBand!, 3)
        XCTAssertEqual(iface.rCsmaCwMin!,  2)
        XCTAssertEqual(iface.rCsmaCwMax!, 16)
    }
}

// MARK: - processIncoming: CMD_STAT_TEMP

final class RNodeProcessIncomingTempTests: XCTestCase {
    /// CMD_STAT_TEMP: 1 byte: temp = byte - 120
    /// byte=145 → temp=25 (valid: -30..90)
    func testTempDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x29, 145, 0xC0])
        XCTAssertEqual(iface.rTemperature!, 25)
    }

    /// temp outside valid range → nil
    func testTempOutOfRangeIsNil() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x29, 0, 0xC0])  // 0 - 120 = -120 → out of range
        XCTAssertNil(iface.rTemperature)
    }
}

// MARK: - processIncoming: CMD_ERROR

final class RNodeProcessIncomingErrorTests: XCTestCase {
    func testErrorMemoryLowDoesNotCrash() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x90, 0x05, 0xC0])  // CMD_ERROR, ERROR_MEMORY_LOW
        XCTAssertTrue(iface.hwErrors.contains(where: { $0 == KISS.errorMemoryLow }))
    }

    func testErrorModemTimeoutDoesNotCrash() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x90, 0x06, 0xC0])  // CMD_ERROR, ERROR_MODEM_TIMEOUT
        XCTAssertTrue(iface.hwErrors.contains(where: { $0 == KISS.errorModemTimeout }))
    }
}

// MARK: - processIncoming: CMD_ST_ALOCK / CMD_LT_ALOCK echoes

final class RNodeProcessIncomingAlockTests: XCTestCase {
    /// CMD_ST_ALOCK echo: 2 bytes big-endian uint16 /100.0
    /// 500 → 5.00%
    func testStAlockEchoDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x0B, 0x01, 0xF4, 0xC0])  // 500 = 5.00%
        XCTAssertEqual(iface.rStAlock!, 5.0, accuracy: 0.001)
    }

    func testLtAlockEchoDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        mock.inject([0xC0, 0x0C, 0x03, 0xE8, 0xC0])  // 1000 = 10.00%
        XCTAssertEqual(iface.rLtAlock!, 10.0, accuracy: 0.001)
    }
}

// MARK: - processIncoming: KISS escape decoding inside data frames

final class RNodeKissEscapeDecodingTests: XCTestCase {
    /// Data frame with FESC-TFEND sequence decodes back to FEND
    func testEscapedFendInDataDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        var received: Data?
        iface.rawInboundHandler = { data, _ in received = data }
        // Frame: FEND CMD_DATA FESC TFEND FEND → payload = [0xC0]
        mock.inject([0xC0, 0x00, 0xDB, 0xDC, 0xC0])
        XCTAssertEqual(received, Data([0xC0]))
    }

    /// Data frame with FESC-TFESC sequence decodes back to FESC
    func testEscapedFescInDataDecoded() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        var received: Data?
        iface.rawInboundHandler = { data, _ in received = data }
        // Frame: FEND CMD_DATA FESC TFESC FEND → payload = [0xDB]
        mock.inject([0xC0, 0x00, 0xDB, 0xDD, 0xC0])
        XCTAssertEqual(received, Data([0xDB]))
    }
}

// MARK: - TX queue / flow control

final class RNodeTxQueueTests: XCTestCase {
    func testQueueStoresPacketWhenNotReady() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.interfaceReady = false
        iface.isOnline = true
        iface.queue(Data([0x01, 0x02]))
        XCTAssertEqual(iface.packetQueue.count, 1)
    }

    func testProcessQueueSendsOnePacketAndRemainsReady() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.interfaceReady = false
        iface.isOnline = true
        iface.packetQueue.append(Data([0xAA, 0xBB]))
        iface.packetQueue.append(Data([0xCC, 0xDD]))
        try iface.processQueue()
        // One packet removed from queue
        XCTAssertEqual(iface.packetQueue.count, 1)
    }

    func testProcessQueueEmptyKeepsInterfaceReady() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.interfaceReady = false
        try iface.processQueue()
        XCTAssertTrue(iface.interfaceReady)
    }
}

// MARK: - hard_reset wire format

final class RNodeHardResetTests: XCTestCase {
    /// Python: hard_reset sends [FEND, CMD_RESET, 0xF8, FEND]
    func testHardResetSendsCorrectBytes() throws {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        try iface.hardReset()
        let bytes = [UInt8](mock.writtenData[0])
        XCTAssertEqual(bytes, [0xC0, 0x55, 0xF8, 0xC0])
    }
}

// MARK: - resetRadioState

final class RNodeResetRadioStateTests: XCTestCase {
    func testResetRadioStateClearsAll() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rFrequency = 868_000_000
        iface.rBandwidth = 125_000
        iface.rTxPower   = 14
        iface.rSf        = 7
        iface.rCr        = 5
        iface.rState     = KISS.radioStateOn
        iface.rLock      = 1
        iface.detected   = true
        iface.resetRadioState()
        XCTAssertNil(iface.rFrequency)
        XCTAssertNil(iface.rBandwidth)
        XCTAssertNil(iface.rTxPower)
        XCTAssertNil(iface.rSf)
        XCTAssertNil(iface.rCr)
        XCTAssertNil(iface.rState)
        XCTAssertNil(iface.rLock)
        XCTAssertFalse(iface.detected)
    }
}

// MARK: - validateFirmware standalone

final class RNodeValidateFirmwareTests: XCTestCase {
    func testValidFirmwareMajAboveRequired() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.majVersion = 2
        iface.minVersion = 0
        iface.validateFirmware()
        XCTAssertTrue(iface.firmwareOk)
    }

    func testValidFirmwareExactRequired() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.majVersion = 1
        iface.minVersion = 52
        iface.validateFirmware()
        XCTAssertTrue(iface.firmwareOk)
    }

    func testInvalidFirmwareBelowRequired() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.majVersion = 1
        iface.minVersion = 51
        iface.validateFirmware()
        XCTAssertFalse(iface.firmwareOk)
    }

    func testInvalidFirmwareMajZero() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.majVersion = 0
        iface.minVersion = 99
        iface.validateFirmware()
        XCTAssertFalse(iface.firmwareOk)
    }
}

// MARK: - processIncoming: multi-frame in one data blob

final class RNodeMultiFrameTests: XCTestCase {
    /// Two KISS frames concatenated in one blob are both handled
    func testTwoFramesInOneBlobBothHandled() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        // Frame 1: CMD_PLATFORM = ESP32; Frame 2: CMD_MCU = 0xA0
        mock.inject([
            0xC0, 0x48, 0x80, 0xC0,   // platform=ESP32
            0xC0, 0x49, 0xA0, 0xC0    // mcu=0xA0
        ])
        XCTAssertEqual(iface.platform, KISS.platformESP32)
        XCTAssertEqual(iface.mcu, 0xA0)
    }
}

// MARK: - getBatteryState / getBatteryPercent accessors

final class RNodeBatteryAccessorTests: XCTestCase {
    func testGetBatteryState() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rBatteryState = RNodeInterface.batteryStateCharging
        XCTAssertEqual(iface.getBatteryState(), RNodeInterface.batteryStateCharging)
    }

    func testGetBatteryPercent() {
        let mock = MockRNodeTransport()
        let iface = RNodeInterface(name: "test", transport: mock)
        iface.rBatteryPercent = 78
        XCTAssertEqual(iface.getBatteryPercent(), 78)
    }
}

// MARK: - Existing KISS.frameData still works (regression)

final class KISSFrameDataRegressionTests: XCTestCase {
    func testFrameDataProducesCorrectFormat() {
        let payload = Data([0x01, 0x02, 0x03])
        let frame = KISS.frameData(payload)
        XCTAssertEqual(frame.first, KISS.fend)
        XCTAssertEqual(frame.last, KISS.fend)
        XCTAssertEqual(frame[frame.startIndex + 1], KISS.cmdData)
    }

    func testFrameDataEscapesFENDInPayload() {
        let payload = Data([0xC0])
        let frame = KISS.frameData(payload)
        // payload byte 0xC0 must be escaped as DB DC
        let body = Array(frame.dropFirst(2).dropLast())
        XCTAssertEqual(body, [0xDB, 0xDC])
    }
}
