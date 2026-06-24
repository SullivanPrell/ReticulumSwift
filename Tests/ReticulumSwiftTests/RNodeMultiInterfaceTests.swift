import XCTest
@testable import ReticulumSwift

// MARK: - Local mock transport (do not import from RNodeInterfaceTests)

private final class MockMultiTransport: RNodeTransport {
    var byteHandler: ((Data) -> Void)?
    var writtenData: [Data] = []
    var isOpen = false

    func open()  throws { isOpen = true }
    func close() { isOpen = false }
    func write(_ data: Data) throws { writtenData.append(data) }

    /// Feed bytes as if they arrived from the hardware.
    func inject(_ bytes: [UInt8]) {
        byteHandler?(Data(bytes))
    }
}

// MARK: - KISS multi-interface command constants

final class KISSMultiInterfaceConstantsTests: XCTestCase {
    // CMD_SEL_INT 0x1F — prefix frame that selects the current subinterface
    func testCmdSelInt()      { XCTAssertEqual(KISS.cmdSelInt,      0x1F) }

    // CMD_INTERFACES 0x71 — detect response carries interface type list
    func testCmdInterfaces()  { XCTAssertEqual(KISS.cmdInterfaces,  0x71) }

    // Incoming data command bytes per channel (CMD_INTn_DATA)
    func testCmdInt0Data()    { XCTAssertEqual(KISS.cmdInt0Data,   0x00) }
    func testCmdInt1Data()    { XCTAssertEqual(KISS.cmdInt1Data,   0x10) }
    func testCmdInt2Data()    { XCTAssertEqual(KISS.cmdInt2Data,   0x20) }
    func testCmdInt3Data()    { XCTAssertEqual(KISS.cmdInt3Data,   0x70) }
    func testCmdInt4Data()    { XCTAssertEqual(KISS.cmdInt4Data,   0x75) }
    func testCmdInt5Data()    { XCTAssertEqual(KISS.cmdInt5Data,   0x90) }
    func testCmdInt6Data()    { XCTAssertEqual(KISS.cmdInt6Data,   0xA0) }
    func testCmdInt7Data()    { XCTAssertEqual(KISS.cmdInt7Data,   0xB0) }
    func testCmdInt8Data()    { XCTAssertEqual(KISS.cmdInt8Data,   0xC0) }
    func testCmdInt9Data()    { XCTAssertEqual(KISS.cmdInt9Data,   0xD0) }
    func testCmdInt10Data()   { XCTAssertEqual(KISS.cmdInt10Data,  0xE0) }
    func testCmdInt11Data()   { XCTAssertEqual(KISS.cmdInt11Data,  0xF0) }

    // Interface type identifiers
    func testSX127X()         { XCTAssertEqual(KISS.sx127x,   0x00) }
    func testSX1276()         { XCTAssertEqual(KISS.sx1276,   0x01) }
    func testSX1278()         { XCTAssertEqual(KISS.sx1278,   0x02) }
    func testSX126X()         { XCTAssertEqual(KISS.sx126x,   0x10) }
    func testSX1262()         { XCTAssertEqual(KISS.sx1262,   0x11) }
    func testSX128X()         { XCTAssertEqual(KISS.sx128x,   0x20) }
    func testSX1280()         { XCTAssertEqual(KISS.sx1280,   0x21) }
}

// MARK: - RNodeSubInterface creation

final class RNodeSubInterfaceCreationTests: XCTestCase {

    func testSubInterfaceStoresAllParameters() {
        let sub = RNodeSubInterface(
            name: "ch0",
            index: 0,
            interfaceType: "SX127X",
            frequency: 868_000_000,
            bandwidth: 125_000,
            txPower: 14,
            sf: 7,
            cr: 5
        )
        XCTAssertEqual(sub.name,      "ch0")
        XCTAssertEqual(sub.index,     0)
        XCTAssertEqual(sub.frequency, 868_000_000)
        XCTAssertEqual(sub.bandwidth, 125_000)
        XCTAssertEqual(sub.txPower,   14)
        XCTAssertEqual(sub.sf,        7)
        XCTAssertEqual(sub.cr,        5)
    }

    func testSubInterfaceDefaultsFlowControlToFalse() {
        let sub = RNodeSubInterface(
            name: "ch0",
            index: 0,
            interfaceType: "SX127X",
            frequency: 868_000_000,
            bandwidth: 125_000,
            txPower: 14,
            sf: 7,
            cr: 5
        )
        XCTAssertFalse(sub.flowControl)
    }

    func testSubInterfaceStoresAirtimeLocks() {
        let sub = RNodeSubInterface(
            name: "ch0",
            index: 0,
            interfaceType: "SX127X",
            frequency: 868_000_000,
            bandwidth: 125_000,
            txPower: 14,
            sf: 7,
            cr: 5,
            stAlock: 5.0,
            ltAlock: 10.0
        )
        XCTAssertEqual(sub.stAlock!, 5.0,  accuracy: 0.001)
        XCTAssertEqual(sub.ltAlock!, 10.0, accuracy: 0.001)
    }

    func testSubInterfaceInterfaceTypeStored() {
        let sub = RNodeSubInterface(
            name: "ch0",
            index: 0,
            interfaceType: "SX128X",
            frequency: 2_400_000_000,
            bandwidth: 203_000,
            txPower: 14,
            sf: 7,
            cr: 5
        )
        XCTAssertEqual(sub.interfaceType, "SX128X")
    }

    func testSubInterfaceInitialStatsAreZero() {
        let sub = RNodeSubInterface(
            name: "ch0",
            index: 0,
            interfaceType: "SX127X",
            frequency: 868_000_000,
            bandwidth: 125_000,
            txPower: 14,
            sf: 7,
            cr: 5
        )
        XCTAssertEqual(sub.rxBytes, 0)
        XCTAssertEqual(sub.txBytes, 0)
    }
}

// MARK: - RNodeMultiInterface creation

final class RNodeMultiInterfaceCreationTests: XCTestCase {

    private func makeTwoSubInterfaces() -> [RNodeSubInterface] {
        [
            RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                              frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5),
            RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                              frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        ]
    }

    func testMultiInterfaceCreatesWithTwoSubInterfaces() throws {
        let transport = MockMultiTransport()
        let subs = makeTwoSubInterfaces()
        let multi = try RNodeMultiInterface(name: "test_multi", transport: transport, subInterfaces: subs)
        XCTAssertEqual(multi.subInterfaces.count, 2)
    }

    func testMultiInterfaceNameStored() throws {
        let transport = MockMultiTransport()
        let subs = makeTwoSubInterfaces()
        let multi = try RNodeMultiInterface(name: "my_multi", transport: transport, subInterfaces: subs)
        XCTAssertEqual(multi.name, "my_multi")
    }

    func testMultiInterfaceRejectsEmptySubInterfaces() {
        let transport = MockMultiTransport()
        XCTAssertThrowsError(
            try RNodeMultiInterface(name: "bad", transport: transport, subInterfaces: [])
        )
    }

    func testMultiInterfaceRejectsTooManySubInterfaces() {
        let transport = MockMultiTransport()
        // More than MAX_SUBINTERFACES (11)
        let subs = (0..<12).map { i in
            RNodeSubInterface(name: "ch\(i)", index: i, interfaceType: "SX127X",
                              frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        }
        XCTAssertThrowsError(
            try RNodeMultiInterface(name: "bad", transport: transport, subInterfaces: subs)
        )
    }

    func testMultiInterfaceSubInterfacesHaveDistinctChannelConfig() throws {
        let transport = MockMultiTransport()
        let subs = makeTwoSubInterfaces()
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: subs)
        XCTAssertEqual(multi.subInterfaces[0].frequency, 868_000_000)
        XCTAssertEqual(multi.subInterfaces[1].frequency, 915_000_000)
        XCTAssertEqual(multi.subInterfaces[0].sf, 7)
        XCTAssertEqual(multi.subInterfaces[1].sf, 8)
    }

    func testMultiInterfaceSubInterfaceCount() throws {
        let transport = MockMultiTransport()
        let subs = (0..<3).map { i in
            RNodeSubInterface(name: "ch\(i)", index: i, interfaceType: "SX127X",
                              frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        }
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: subs)
        XCTAssertEqual(multi.subInterfaces.count, 3)
    }
}

// MARK: - RNodeMultiInterface constants

final class RNodeMultiInterfaceConstantsTests: XCTestCase {
    func testMaxSubInterfaces()       { XCTAssertEqual(RNodeMultiInterface.maxSubInterfaces, 11) }
    func testHwMtu()                  { XCTAssertEqual(RNodeMultiInterface.hwMtuValue, 508) }
    func testRequiredFwVerMaj()       { XCTAssertEqual(RNodeMultiInterface.requiredFwVerMaj, 1) }
    func testRequiredFwVerMin()       { XCTAssertEqual(RNodeMultiInterface.requiredFwVerMin, 74) }
    func testReconnectWait()          { XCTAssertEqual(RNodeMultiInterface.reconnectWait, 5) }
}

// MARK: - CMD_SEL_INT wire format (outgoing config commands)

final class RNodeMultiInterfaceSelIntCommandTests: XCTestCase {

    // Outgoing config command: [FEND CMD_SEL_INT index FEND FEND cmd data FEND]
    // Python: kiss_command = bytes([KISS.FEND])+bytes([KISS.CMD_SEL_INT])+bytes([interface.index])
    //         +bytes([KISS.FEND])+bytes([KISS.FEND])+bytes([KISS.CMD_FREQUENCY])+data+bytes([KISS.FEND])

    func testSetFrequencyForSubInterface0() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])

        try multi.setFrequency(for: sub0)
        // Expected: [FEND CMD_SEL_INT 0x00 FEND FEND CMD_FREQUENCY 0x33 0xBC 0xA1 0x00 FEND]
        // 868_000_000 = 0x33BCA100
        XCTAssertEqual(transport.writtenData.count, 1)
        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[0], KISS.fend)
        XCTAssertEqual(bytes[1], KISS.cmdSelInt)
        XCTAssertEqual(bytes[2], 0)          // index 0
        XCTAssertEqual(bytes[3], KISS.fend)
        XCTAssertEqual(bytes[4], KISS.fend)
        XCTAssertEqual(bytes[5], KISS.cmdFrequency)
        XCTAssertEqual(bytes[6],  0x33)
        XCTAssertEqual(bytes[7],  0xBC)
        XCTAssertEqual(bytes[8],  0xA1)
        XCTAssertEqual(bytes[9],  0x00)
        XCTAssertEqual(bytes[10], KISS.fend)
    }

    func testSetFrequencyForSubInterface1() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 433_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])

        try multi.setFrequency(for: sub1)
        // 433_000_000 = 0x19CF0E40
        XCTAssertEqual(transport.writtenData.count, 1)
        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[1], KISS.cmdSelInt)
        XCTAssertEqual(bytes[2], 1)   // index 1
        XCTAssertEqual(bytes[5], KISS.cmdFrequency)
        XCTAssertEqual(bytes[6],  0x19)
        XCTAssertEqual(bytes[7],  0xCF)
        XCTAssertEqual(bytes[8],  0x0E)
        XCTAssertEqual(bytes[9],  0x40)
    }

    func testSetBandwidthForSubInterface() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.setBandwidth(for: sub0)
        // 125_000 = 0x0001E848
        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[1], KISS.cmdSelInt)
        XCTAssertEqual(bytes[2], 0)
        XCTAssertEqual(bytes[5], KISS.cmdBandwidth)
        XCTAssertEqual(bytes[6], 0x00)
        XCTAssertEqual(bytes[7], 0x01)
        XCTAssertEqual(bytes[8], 0xE8)
        XCTAssertEqual(bytes[9], 0x48)
    }

    func testSetTxPowerForSubInterface() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.setTxPower(for: sub0)
        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[1], KISS.cmdSelInt)
        XCTAssertEqual(bytes[5], KISS.cmdTxpower)
        XCTAssertEqual(bytes[6], 14)
    }

    func testSetSpreadingFactorForSubInterface() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.setSpreadingFactor(for: sub0)
        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[1], KISS.cmdSelInt)
        XCTAssertEqual(bytes[5], KISS.cmdSf)
        XCTAssertEqual(bytes[6], 7)
    }

    func testSetCodingRateForSubInterface() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.setCodingRate(for: sub0)
        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[1], KISS.cmdSelInt)
        XCTAssertEqual(bytes[5], KISS.cmdCr)
        XCTAssertEqual(bytes[6], 5)
    }

    func testSetRadioStateForSubInterface() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.setRadioState(KISS.radioStateOn, for: sub0)
        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[1], KISS.cmdSelInt)
        XCTAssertEqual(bytes[5], KISS.cmdRadioState)
        XCTAssertEqual(bytes[6], KISS.radioStateOn)
    }

    func testSetStAlockForSubInterface() throws {
        let transport = MockMultiTransport()
        var sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        sub0.stAlock = 5.0
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.setStAlock(for: sub0)
        // int(5.0*100)=500=0x01F4
        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[1], KISS.cmdSelInt)
        XCTAssertEqual(bytes[5], KISS.cmdStAlock)
        XCTAssertEqual(bytes[6], 0x01)
        XCTAssertEqual(bytes[7], 0xF4)
    }

    func testSetStAlockNilSendsNothing() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.setStAlock(for: sub0)
        XCTAssertEqual(transport.writtenData.count, 0)
    }

    func testSetLtAlockForSubInterface() throws {
        let transport = MockMultiTransport()
        var sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        sub0.ltAlock = 10.0
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.setLtAlock(for: sub0)
        // int(10.0*100)=1000=0x03E8
        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[5], KISS.cmdLtAlock)
        XCTAssertEqual(bytes[6], 0x03)
        XCTAssertEqual(bytes[7], 0xE8)
    }
}

// MARK: - initRadio per subinterface

final class RNodeMultiInterfaceInitRadioTests: XCTestCase {

    func testInitRadioSendsSelIntPrefixedFrames() throws {
        let transport = MockMultiTransport()
        var sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.initRadio(for: &sub0)
        // Should have at least 6 writes: freq, bw, txpower, sf, cr, radiostate
        XCTAssertGreaterThanOrEqual(transport.writtenData.count, 6)

        // Every write must start with: FEND CMD_SEL_INT index FEND FEND ...
        for frame in transport.writtenData {
            let bytes = [UInt8](frame)
            XCTAssertEqual(bytes[0], KISS.fend,       "All config frames must begin with FEND")
            XCTAssertEqual(bytes[1], KISS.cmdSelInt,  "All config frames must have CMD_SEL_INT as 2nd byte")
            XCTAssertEqual(bytes[2], 0,               "Sub-interface 0 has index 0")
            XCTAssertEqual(bytes[3], KISS.fend,       "CMD_SEL_INT frame terminates with FEND")
            XCTAssertEqual(bytes[4], KISS.fend,       "Payload frame begins with FEND")
        }
    }

    func testInitRadioForSubInterface1UsesCorrectIndex() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        var sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])
        try multi.initRadio(for: &sub1)
        for frame in transport.writtenData {
            let bytes = [UInt8](frame)
            XCTAssertEqual(bytes[2], 1, "Sub-interface 1 has index 1")
        }
    }

    func testInitRadioSendsFrequencyFirst() throws {
        let transport = MockMultiTransport()
        var sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.initRadio(for: &sub0)
        let firstBytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(firstBytes[5], KISS.cmdFrequency)
    }

    func testInitRadioSendsRadioStateOnLast() throws {
        let transport = MockMultiTransport()
        var sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.initRadio(for: &sub0)
        let lastBytes = [UInt8](transport.writtenData.last!)
        XCTAssertEqual(lastBytes[5], KISS.cmdRadioState)
        XCTAssertEqual(lastBytes[6], KISS.radioStateOn)
    }

    func testInitRadioSetsSubInterfaceStateOn() throws {
        let transport = MockMultiTransport()
        var sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.initRadio(for: &sub0)
        XCTAssertEqual(sub0.state, KISS.radioStateOn)
    }

    func testInitAllRadios() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])
        // initAllRadios() configures both
        try multi.initAllRadios()
        // Should have at least 12 writes (6 per sub-interface)
        XCTAssertGreaterThanOrEqual(transport.writtenData.count, 12)
    }
}

// MARK: - Outgoing packet multiplexing

final class RNodeMultiInterfaceOutgoingTests: XCTestCase {

    // Python: process_outgoing(data, interface)
    // Frame format: [FEND CMD_SEL_INT index FEND FEND CMD_DATA escaped_data FEND]
    func testProcessOutgoingSubInterface0() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])

        let payload = Data([0x01, 0x02, 0x03])
        try multi.processOutgoing(payload, subInterface: sub0)

        XCTAssertEqual(transport.writtenData.count, 1)
        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[0], KISS.fend)
        XCTAssertEqual(bytes[1], KISS.cmdSelInt)
        XCTAssertEqual(bytes[2], 0)           // index 0
        XCTAssertEqual(bytes[3], KISS.fend)
        XCTAssertEqual(bytes[4], KISS.fend)
        XCTAssertEqual(bytes[5], KISS.cmdData)
        // payload bytes (no escaping needed for 0x01, 0x02, 0x03)
        XCTAssertEqual(bytes[6], 0x01)
        XCTAssertEqual(bytes[7], 0x02)
        XCTAssertEqual(bytes[8], 0x03)
        XCTAssertEqual(bytes[9], KISS.fend)
    }

    func testProcessOutgoingSubInterface1() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])

        let payload = Data([0xAA])
        try multi.processOutgoing(payload, subInterface: sub1)

        let bytes = [UInt8](transport.writtenData[0])
        XCTAssertEqual(bytes[2], 1)  // index 1
    }

    func testProcessOutgoingEscapesPayload() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])

        // Payload containing FEND byte (0xC0) must be escaped
        let payload = Data([0xC0])
        try multi.processOutgoing(payload, subInterface: sub0)

        let bytes = [UInt8](transport.writtenData[0])
        // After [FEND CMD_SEL_INT 0 FEND FEND CMD_DATA], next bytes should be [FESC TFEND] for the escaped 0xC0
        XCTAssertEqual(bytes[6], KISS.fesc)
        XCTAssertEqual(bytes[7], KISS.tfend)
        XCTAssertEqual(bytes[8], KISS.fend)   // frame terminator
    }

    func testProcessOutgoingNilSubInterfaceDoesNotWrite() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        // Calling without a subinterface (direct call on multi) should not write
        try multi.processOutgoing(Data([0x01]), subInterface: nil)
        XCTAssertEqual(transport.writtenData.count, 0)
    }
}

// MARK: - Incoming packet dispatch (CMD_INTn_DATA)

final class RNodeMultiInterfaceIncomingDispatchTests: XCTestCase {

    // Python readLoop: if command is CMD_INTn_DATA, data goes to subinterfaces[selected_index]
    // The CMD_SEL_INT command sets selected_index.
    // So the flow is:
    //   1. Receive [FEND CMD_SEL_INT 0 FEND] → selected_index = 0
    //   2. Receive [FEND CMD_INT0_DATA data FEND] → subinterfaces[0].process_incoming(data)
    //
    // OR the hardware can use the CMD_INTn_DATA command byte directly to indicate which interface:
    //   CMD_INT0_DATA = 0x00 → sub 0
    //   CMD_INT1_DATA = 0x10 → sub 1
    //   etc.

    func testIncomingFrameWithSelIntDispatchesToCorrectSubInterface() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])

        var receivedByChannel: [Int: Data] = [:]
        multi.rawInboundHandler = { data, iface in
            if let sub = iface as? RNodeSubInterface {
                receivedByChannel[sub.index] = data
            }
        }

        // Select sub0, then send data
        transport.inject([
            0xC0, KISS.cmdSelInt, 0x00, 0xC0,   // Select interface 0
            0xC0, KISS.cmdData,   0x01, 0x02, 0xC0  // CMD_DATA (CMD_INT0_DATA) payload
        ])

        XCTAssertNotNil(receivedByChannel[0])
        XCTAssertNil(receivedByChannel[1])
        XCTAssertEqual(receivedByChannel[0], Data([0x01, 0x02]))
    }

    func testIncomingFrameForSubInterface1() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])

        var receivedByChannel: [Int: Data] = [:]
        multi.rawInboundHandler = { data, iface in
            if let sub = iface as? RNodeSubInterface {
                receivedByChannel[sub.index] = data
            }
        }

        // Select sub1, then send data
        transport.inject([
            0xC0, KISS.cmdSelInt, 0x01, 0xC0,
            0xC0, KISS.cmdData,   0xAA, 0xBB, 0xC0
        ])

        XCTAssertNil(receivedByChannel[0])
        XCTAssertNotNil(receivedByChannel[1])
        XCTAssertEqual(receivedByChannel[1], Data([0xAA, 0xBB]))
    }

    func testIncomingCmdInt1DataDirectCommandDispatchesToSub1() throws {
        // The hardware can also use CMD_INT1_DATA (0x10) directly as command byte
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])

        var receivedBySub1: Data?
        multi.rawInboundHandler = { data, iface in
            if let sub = iface as? RNodeSubInterface, sub.index == 1 {
                receivedBySub1 = data
            }
        }

        // Use CMD_INT1_DATA (0x10) directly — maps to subinterface 1
        transport.inject([0xC0, KISS.cmdInt1Data, 0xDE, 0xAD, 0xC0])

        XCTAssertEqual(receivedBySub1, Data([0xDE, 0xAD]))
    }

    func testIncomingCmdInt0DataDirectCommand() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])

        var received: Data?
        multi.rawInboundHandler = { data, _ in received = data }

        // CMD_INT0_DATA = 0x00 = cmdData
        transport.inject([0xC0, KISS.cmdInt0Data, 0x11, 0x22, 0xC0])
        XCTAssertEqual(received, Data([0x11, 0x22]))
    }

    func testIncomingSelIntChangesSelectedIndex() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])
        XCTAssertEqual(multi.selectedIndex, 0)  // default

        transport.inject([0xC0, KISS.cmdSelInt, 0x01, 0xC0])
        XCTAssertEqual(multi.selectedIndex, 1)
    }

    func testIncomingFrequencyEchoGoesToCorrectSubInterface() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])

        // Select sub1 then inject frequency echo for 915_000_000
        transport.inject([
            0xC0, KISS.cmdSelInt, 0x01, 0xC0,
            0xC0, KISS.cmdFrequency, 0x36, 0x89, 0xCA, 0xC0, 0xC0   // 915_000_000 but last byte 0xC0 ends frame
        ])
        // 915_000_000 = 0x3689CAC0 but FEND at 0xC0 position would need escaping. Use a simpler frequency.
        // Let's inject 868_000_000 = 0x33BCA100 instead for sub1.
        // First reset writtenData for clarity
        transport.inject([
            0xC0, KISS.cmdSelInt, 0x01, 0xC0,
            0xC0, KISS.cmdFrequency, 0x33, 0xBC, 0xA1, 0x00, 0xC0
        ])

        // sub1 should have rFrequency set; sub0 should still be nil
        XCTAssertEqual(multi.subInterfaces[1].rFrequency, 868_000_000)
    }
}

// MARK: - Incoming telemetry routed to correct subinterface

final class RNodeMultiInterfaceTelemetryTests: XCTestCase {

    private func makeMulti(transport: MockMultiTransport) throws -> RNodeMultiInterface {
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        return try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])
    }

    func testRssiEchoGoesToSelectedSubInterface() throws {
        let transport = MockMultiTransport()
        let multi = try makeMulti(transport: transport)
        // Select sub1, inject RSSI
        transport.inject([
            0xC0, KISS.cmdSelInt, 0x01, 0xC0,
            0xC0, KISS.cmdStatRssi, 214, 0xC0
        ])
        XCTAssertEqual(multi.subInterfaces[1].rStatRssi, 214 - 157)  // = 57
        XCTAssertNil(multi.subInterfaces[0].rStatRssi)
    }

    func testSnrEchoGoesToSelectedSubInterface() throws {
        let transport = MockMultiTransport()
        let multi = try makeMulti(transport: transport)
        transport.inject([
            0xC0, KISS.cmdSelInt, 0x00, 0xC0,
            0xC0, KISS.cmdStatSnr, 0x08, 0xC0  // SNR = 2.0
        ])
        XCTAssertEqual(multi.subInterfaces[0].rStatSnr!, Float(2.0), accuracy: 0.001)
        XCTAssertNil(multi.subInterfaces[1].rStatSnr)
    }

    func testBandwidthEchoGoesToSelectedSubInterface() throws {
        let transport = MockMultiTransport()
        let multi = try makeMulti(transport: transport)
        transport.inject([
            0xC0, KISS.cmdSelInt, 0x01, 0xC0,
            0xC0, KISS.cmdBandwidth, 0x00, 0x01, 0xE8, 0x48, 0xC0  // 125_000
        ])
        XCTAssertEqual(multi.subInterfaces[1].rBandwidth, 125_000)
        XCTAssertNil(multi.subInterfaces[0].rBandwidth)
    }

    func testRadioStateEchoGoesToSelectedSubInterface() throws {
        let transport = MockMultiTransport()
        let multi = try makeMulti(transport: transport)
        transport.inject([
            0xC0, KISS.cmdSelInt, 0x00, 0xC0,
            0xC0, KISS.cmdRadioState, 0x01, 0xC0
        ])
        XCTAssertEqual(multi.subInterfaces[0].rState, KISS.radioStateOn)
        XCTAssertNil(multi.subInterfaces[1].rState)
    }
}

// MARK: - CMD_INTERFACES response parsing

final class RNodeMultiInterfaceCmdInterfacesTests: XCTestCase {

    func testCmdInterfacesBuildsSubInterfaceTypeList() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])

        // Python: command_buffer gets 2 bytes per interface; each pair is [unknown, interface_type]
        // CMD_INTERFACES frame: [FEND CMD_INTERFACES type1_vport type1_type ... FEND]
        // Each 2-byte pair: vport byte + interface type byte
        // SX127X = 0x00, SX1276 = 0x01, SX128X = 0x20
        transport.inject([
            0xC0, KISS.cmdInterfaces, 0x00, KISS.sx1276, 0x01, KISS.sx1276, 0xC0
        ])
        // Two interfaces reported: both SX127X
        XCTAssertEqual(multi.subInterfaceTypes.count, 2)
        XCTAssertEqual(multi.subInterfaceTypes[0], "SX127X")
        XCTAssertEqual(multi.subInterfaceTypes[1], "SX127X")
    }

    func testCmdInterfacesSX128XType() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX128X",
                                     frequency: 2_400_000_000, bandwidth: 203_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])

        transport.inject([0xC0, KISS.cmdInterfaces, 0x00, KISS.sx1280, 0xC0])
        XCTAssertEqual(multi.subInterfaceTypes.count, 1)
        XCTAssertEqual(multi.subInterfaceTypes[0], "SX128X")
    }
}

// MARK: - Per-subinterface stats tracking

final class RNodeMultiInterfaceStatsTests: XCTestCase {

    func testRxBytesTrackedPerSubInterface() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])
        multi.rawInboundHandler = { _, _ in }

        // Inject 3 bytes on sub0
        transport.inject([0xC0, KISS.cmdSelInt, 0x00, 0xC0,
                          0xC0, KISS.cmdData, 0x01, 0x02, 0x03, 0xC0])
        XCTAssertEqual(multi.subInterfaces[0].rxBytes, 3)
        XCTAssertEqual(multi.subInterfaces[1].rxBytes, 0)
    }

    func testTxBytesTrackedPerSubInterface() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1])

        let payload = Data([0xAA, 0xBB, 0xCC])
        try multi.processOutgoing(payload, subInterface: sub1)
        XCTAssertEqual(multi.subInterfaces[0].txBytes, 0)
        XCTAssertEqual(multi.subInterfaces[1].txBytes, 3)
    }

    func testRxBytesAccumulateAcrossMultipleFrames() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        multi.rawInboundHandler = { _, _ in }

        transport.inject([0xC0, KISS.cmdSelInt, 0x00, 0xC0,
                          0xC0, KISS.cmdData, 0x01, 0x02, 0xC0])  // 2 bytes
        transport.inject([0xC0, KISS.cmdSelInt, 0x00, 0xC0,
                          0xC0, KISS.cmdData, 0x03, 0xC0])         // 1 byte
        XCTAssertEqual(multi.subInterfaces[0].rxBytes, 3)
    }
}

// MARK: - Detect command

final class RNodeMultiInterfaceDetectTests: XCTestCase {
    func testDetectSendsCorrectBytesIncludingCmdInterfaces() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.detect()
        // Python detect():
        // [FEND CMD_DETECT DETECT_REQ FEND CMD_FW_VERSION 0x00 FEND CMD_PLATFORM 0x00
        //  FEND CMD_MCU 0x00 FEND CMD_INTERFACES 0x00 FEND]
        XCTAssertEqual(transport.writtenData.count, 1)
        let bytes = [UInt8](transport.writtenData[0])
        let expected: [UInt8] = [
            0xC0, KISS.cmdDetect,    KISS.detectReq,
            0xC0, KISS.cmdFwVersion, 0x00,
            0xC0, KISS.cmdPlatform,  0x00,
            0xC0, KISS.cmdMcu,       0x00,
            0xC0, KISS.cmdInterfaces,0x00,
            0xC0
        ]
        XCTAssertEqual(bytes, expected)
    }
}

// MARK: - Detect response updates multi-interface state

final class RNodeMultiInterfaceDetectResponseTests: XCTestCase {
    func testDetectResponseSetsDetected() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        XCTAssertFalse(multi.detected)
        transport.inject([0xC0, KISS.cmdDetect, KISS.detectResp, 0xC0])
        XCTAssertTrue(multi.detected)
    }

    func testFwVersionParsed() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        transport.inject([0xC0, KISS.cmdFwVersion, 0x01, 0x4A, 0xC0])  // v1.74
        XCTAssertEqual(multi.majVersion, 1)
        XCTAssertEqual(multi.minVersion, 74)
        XCTAssertTrue(multi.firmwareOk)
    }

    func testFwVersionBelowRequiredNotOk() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        transport.inject([0xC0, KISS.cmdFwVersion, 0x01, 0x30, 0xC0])  // v1.48 — too old
        XCTAssertFalse(multi.firmwareOk)
    }

    func testPlatformParsed() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        transport.inject([0xC0, KISS.cmdPlatform, KISS.platformESP32, 0xC0])
        XCTAssertEqual(multi.platform, KISS.platformESP32)
    }
}

// MARK: - KISS.interfaceTypeToString helper

final class KISSInterfaceTypeToStringTests: XCTestCase {
    func testSX127XTypes() {
        XCTAssertEqual(KISS.interfaceTypeToString(KISS.sx127x),  "SX127X")
        XCTAssertEqual(KISS.interfaceTypeToString(KISS.sx1276),  "SX127X")
        XCTAssertEqual(KISS.interfaceTypeToString(KISS.sx1278),  "SX127X")
    }

    func testSX126XTypes() {
        XCTAssertEqual(KISS.interfaceTypeToString(KISS.sx126x),  "SX126X")
        XCTAssertEqual(KISS.interfaceTypeToString(KISS.sx1262),  "SX126X")
    }

    func testSX128XTypes() {
        XCTAssertEqual(KISS.interfaceTypeToString(KISS.sx128x),  "SX128X")
        XCTAssertEqual(KISS.interfaceTypeToString(KISS.sx1280),  "SX128X")
    }

    func testUnknownTypeFallsBackToSX127X() {
        XCTAssertEqual(KISS.interfaceTypeToString(0xFF), "SX127X")
    }
}

// MARK: - validateFirmware for RNodeMultiInterface

final class RNodeMultiInterfaceValidateFirmwareTests: XCTestCase {

    func testValidFirmwareAtExactRequired() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        multi.majVersion = 1
        multi.minVersion = 74
        multi.validateFirmware()
        XCTAssertTrue(multi.firmwareOk)
    }

    func testValidFirmwareMajAboveRequired() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        multi.majVersion = 2
        multi.minVersion = 0
        multi.validateFirmware()
        XCTAssertTrue(multi.firmwareOk)
    }

    func testInvalidFirmwareBelowRequired() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        multi.majVersion = 1
        multi.minVersion = 73
        multi.validateFirmware()
        XCTAssertFalse(multi.firmwareOk)
    }
}

// MARK: - isOnline state

final class RNodeMultiInterfaceOnlineStateTests: XCTestCase {
    func testIsOnlineIsFalseInitially() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        XCTAssertFalse(multi.isOnline)
    }

    func testStartOpensTransport() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.start()
        XCTAssertTrue(transport.isOpen)
    }

    func testStopClosesTransport() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.start()
        multi.stop()
        XCTAssertFalse(transport.isOpen)
        XCTAssertFalse(multi.isOnline)
    }
}

// MARK: - description / __str__

final class RNodeMultiInterfaceDescriptionTests: XCTestCase {
    func testDescriptionIncludesName() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test_radio", transport: transport, subInterfaces: [sub0])
        XCTAssertTrue(multi.description.contains("test_radio"))
    }

    func testSubInterfaceDescriptionIncludesParentAndName() throws {
        let sub = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                    frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        XCTAssertTrue(sub.description.contains("ch0"))
    }
}

// MARK: - Subinterface enumeration

final class RNodeMultiInterfaceEnumerationTests: XCTestCase {
    func testSubInterfacesByIndex() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let sub1 = RNodeSubInterface(name: "ch1", index: 1, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 8, cr: 5)
        let sub2 = RNodeSubInterface(name: "ch2", index: 2, interfaceType: "SX127X",
                                     frequency: 433_000_000, bandwidth: 125_000, txPower: 14, sf: 9, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0, sub1, sub2])

        XCTAssertEqual(multi.subInterfaces[0].name, "ch0")
        XCTAssertEqual(multi.subInterfaces[1].name, "ch1")
        XCTAssertEqual(multi.subInterfaces[2].name, "ch2")
    }
}

// MARK: - KISS escape in config commands (regression)

final class RNodeMultiInterfaceKISSEscapeTests: XCTestCase {
    // 915_000_000 = 0x3689CAC0 — last byte is 0xC0 (FEND), must be escaped
    // Frame: [FEND CMD_SEL_INT 0 FEND FEND CMD_FREQUENCY 0x36 0x89 0xCA 0xDB 0xDC FEND]
    func testSetFrequency915MHzEscapedInMultiFrame() throws {
        let transport = MockMultiTransport()
        let sub0 = RNodeSubInterface(name: "ch0", index: 0, interfaceType: "SX127X",
                                     frequency: 915_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
        let multi = try RNodeMultiInterface(name: "test", transport: transport, subInterfaces: [sub0])
        try multi.setFrequency(for: sub0)
        let bytes = [UInt8](transport.writtenData[0])
        // Header: [FEND CMD_SEL_INT 0 FEND FEND CMD_FREQUENCY]
        XCTAssertEqual(bytes[5], KISS.cmdFrequency)
        XCTAssertEqual(bytes[6], 0x36)
        XCTAssertEqual(bytes[7], 0x89)
        XCTAssertEqual(bytes[8], 0xCA)
        // 0xC0 → escaped as 0xDB 0xDC
        XCTAssertEqual(bytes[9],  KISS.fesc)
        XCTAssertEqual(bytes[10], KISS.tfend)
        XCTAssertEqual(bytes[11], KISS.fend)
    }
}
