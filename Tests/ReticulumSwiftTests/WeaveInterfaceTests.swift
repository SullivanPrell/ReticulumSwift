import XCTest
@testable import ReticulumSwift

// MARK: - Mock serial transport for Weave tests

private final class MockWeaveTransport: SerialPortTransport {
    var written:    [Data] = []
    var readCB:     ((Data) -> Void)?
    var openCalled  = false
    var closeCalled = false
    var isOpen:     Bool   = false

    func open(port: String, baudRate: Int,
              dataBits: Int, parity: SerialParity, stopBits: Int) throws {
        openCalled = true
        isOpen = true
        XCTAssertEqual(baudRate, WDCLTransport.speed)
    }

    @discardableResult
    func write(_ data: Data) throws -> Int {
        written.append(data)
        return data.count
    }

    func setReadCallback(_ cb: @escaping (Data) -> Void) { readCB = cb }
    func close() { closeCalled = true; isOpen = false }

    /// Simulate the device sending `raw` bytes (HDLC-framed WDCL frame).
    func simulateReceive(_ raw: Data) { readCB?(raw) }
}

// MARK: - WeaveInterfaceTests

final class WeaveInterfaceTests: XCTestCase {

    // MARK: - WDCL constant tests

    func testWDCLPacketTypes() {
        XCTAssertEqual(WDCL.tDiscover,    0x00)
        XCTAssertEqual(WDCL.tConnect,     0x01)
        XCTAssertEqual(WDCL.tCmd,         0x02)
        XCTAssertEqual(WDCL.tLog,         0x03)
        XCTAssertEqual(WDCL.tDisp,        0x04)
        XCTAssertEqual(WDCL.tEndpointPkt, 0x05)
        XCTAssertEqual(WDCL.tEncapProto,  0x06)
    }

    func testWDCLBroadcast() {
        XCTAssertEqual(WDCL.broadcast, Data([0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertEqual(WDCL.broadcast.count, 4)
    }

    func testWDCLHeaderMinSize() {
        XCTAssertEqual(WDCL.headerMinSize, 5)  // 4-byte switch_id + 1-byte type
    }

    func testWDCLHandshakeTimeout() {
        XCTAssertEqual(WDCL.handshakeTimeout, 2.0)
    }

    // MARK: - WeaveCmd constant tests

    func testWeaveCmdConstants() {
        XCTAssertEqual(WeaveCmd.endpointPkt,   0x0001)
        XCTAssertEqual(WeaveCmd.endpointsList,  0x0100)
        XCTAssertEqual(WeaveCmd.remoteDisplay,  0x0A00)
        XCTAssertEqual(WeaveCmd.remoteInput,    0x0A01)
    }

    // MARK: - WeaveEvt constant tests

    func testWeaveEvtSystemEvents() {
        XCTAssertEqual(WeaveEvt.etMsg,         0x0000)
        XCTAssertEqual(WeaveEvt.etSystemBoot,  0x0001)
        XCTAssertEqual(WeaveEvt.etCoreInit,    0x0002)
        // RNS 1.3.8 (commit dd3ddb9d): board hardware initialization event.
        XCTAssertEqual(WeaveEvt.etBoardInit,   0x0003)
    }

    func testWeaveEvtDriverEvents() {
        XCTAssertEqual(WeaveEvt.etDrvUartInit,       0x1000)
        XCTAssertEqual(WeaveEvt.etDrvUsbCdcInit,     0x1010)
        XCTAssertEqual(WeaveEvt.etDrvUsbCdcHostAvail, 0x1011)
        XCTAssertEqual(WeaveEvt.etDrvUsbCdcConnected, 0x1014)
        XCTAssertEqual(WeaveEvt.etDrvI2cInit,        0x1020)
        XCTAssertEqual(WeaveEvt.etDrvNvsInit,        0x1030)
        XCTAssertEqual(WeaveEvt.etDrvCryptoInit,     0x1040)
        XCTAssertEqual(WeaveEvt.etDrvDisplayInit,    0x1050)
        XCTAssertEqual(WeaveEvt.etDrvW80211Init,     0x1060)
    }

    func testWeaveEvtKernelEvents() {
        XCTAssertEqual(WeaveEvt.etKrnLoggerInit, 0x2000)
        XCTAssertEqual(WeaveEvt.etKrnUiInit,     0x2010)
    }

    func testWeaveEvtProtocolWDCL() {
        XCTAssertEqual(WeaveEvt.etProtocolWdclInit,         0x3000)
        XCTAssertEqual(WeaveEvt.etProtocolWdclRunning,      0x3001)
        XCTAssertEqual(WeaveEvt.etProtocolWdclConnection,   0x3002)
        XCTAssertEqual(WeaveEvt.etProtocolWdclHostEndpoint, 0x3003)
    }

    func testWeaveEvtProtocolWeave() {
        XCTAssertEqual(WeaveEvt.etProtocolWeaveInit,      0x3100)
        XCTAssertEqual(WeaveEvt.etProtocolWeaveRunning,   0x3101)
        XCTAssertEqual(WeaveEvt.etProtocolWeaveEpAlive,   0x3102)
        XCTAssertEqual(WeaveEvt.etProtocolWeaveEpTimeout, 0x3103)
        XCTAssertEqual(WeaveEvt.etProtocolWeaveEpVia,     0x3104)
    }

    func testWeaveEvtStatEvents() {
        XCTAssertEqual(WeaveEvt.etStatState,   0xE000)
        XCTAssertEqual(WeaveEvt.etStatUptime,  0xE001)
        XCTAssertEqual(WeaveEvt.etStatCpu,     0xE003)
        XCTAssertEqual(WeaveEvt.etStatTaskCpu, 0xE004)
        XCTAssertEqual(WeaveEvt.etStatMemory,  0xE005)
        XCTAssertEqual(WeaveEvt.etStatStorage, 0xE006)
    }

    func testWeaveEvtErrorEvents() {
        XCTAssertEqual(WeaveEvt.etSyserrMemExhausted, 0xF000)
    }

    // MARK: - WeaveDevice constant tests

    func testWeaveDeviceWireSizes() {
        XCTAssertEqual(WeaveDevice.switchIDLen,   4)
        XCTAssertEqual(WeaveDevice.endpointIDLen, 8)
        XCTAssertEqual(WeaveDevice.flowseqLen,    2)
        XCTAssertEqual(WeaveDevice.hmacLen,       8)
        XCTAssertEqual(WeaveDevice.authLen,       16)
        XCTAssertEqual(WeaveDevice.pubkeySize,    32)
        XCTAssertEqual(WeaveDevice.prvkeySize,    64)
        XCTAssertEqual(WeaveDevice.signatureLen,  64)
    }

    // MARK: - WDCLTransport constant tests

    func testWDCLTransportConstants() {
        XCTAssertEqual(WDCLTransport.speed,       3_000_000)
        XCTAssertEqual(WDCLTransport.switchIDLen, 4)
        XCTAssertEqual(WDCLTransport.pubkeySize,  32)
        XCTAssertEqual(WDCLTransport.signatureLen, 64)
    }

    // MARK: - WeaveInterface constant tests

    func testWeaveInterfaceConstants() {
        XCTAssertEqual(WeaveInterface.hwMtuValue,      1024)
        XCTAssertEqual(WeaveInterface.defaultIfacSize, 16)
        XCTAssertEqual(WeaveInterface.peeringTimeout,  20.0)
        XCTAssertEqual(WeaveInterface.bitrateGuess,    250_000)
        XCTAssertEqual(WeaveInterface.multiIfDequeTTL, 0.75)
        XCTAssertEqual(WeaveInterface.multiIfDequeLen, 48)
    }

    func testWeaveEndpointQueueLen() {
        XCTAssertEqual(WeaveEndpoint.queueLen, 1024)
    }

    // MARK: - WeaveLogFrame initialization

    func testWeaveLogFrameInit() {
        let frame = WeaveLogFrame(timestamp: 1.5, level: 3, event: 0x3002,
                                  data: Data([0x01, 0x02]))
        XCTAssertEqual(frame.timestamp, 1.5)
        XCTAssertEqual(frame.level,     3)
        XCTAssertEqual(frame.event,     0x3002)
        XCTAssertEqual(frame.data,      Data([0x01, 0x02]))
    }

    // MARK: - WeaveEndpoint initialization

    func testWeaveEndpointInit() {
        let addr     = Data(repeating: 0xAB, count: 8)
        let endpoint = WeaveEndpoint(endpointAddr: addr)
        XCTAssertEqual(endpoint.endpointAddr, addr)
        XCTAssertNil(endpoint.viaSwitchID)
        XCTAssertTrue(endpoint.lastSeen.timeIntervalSinceNow > -1)
    }

    // MARK: - WDCLTransport identity

    func testWDCLTransportIdentity() {
        let t = WDCLTransport(transport: MockWeaveTransport())
        XCTAssertEqual(t.switchID.count, 4)
        XCTAssertEqual(t.switchPubBytes.count, 32)
        // switchID is the last 4 bytes of switchPubBytes
        XCTAssertEqual(t.switchID, Data(t.switchPubBytes.suffix(4)))
    }

    func testWDCLTransportSign() {
        let t    = WDCLTransport(transport: MockWeaveTransport())
        let data = Data([0x01, 0x02, 0x03])
        let sig  = t.sign(data)
        XCTAssertEqual(sig.count, 64)  // Ed25519 signature is 64 bytes
    }

    // MARK: - WDCLTransport open / close

    func testWDCLTransportOpenClose() throws {
        let mock = MockWeaveTransport()
        let t    = WDCLTransport(transport: mock)
        XCTAssertFalse(t.isOnline)
        try t.open(port: "/dev/test")
        XCTAssertTrue(t.isOnline)
        XCTAssertTrue(mock.openCalled)
        t.close()
        XCTAssertFalse(t.isOnline)
        XCTAssertTrue(mock.closeCalled)
    }

    // MARK: - WDCLTransport broadcast

    func testWDCLTransportBroadcast() throws {
        let mock = MockWeaveTransport()
        let t    = WDCLTransport(transport: mock)
        try t.open(port: "/dev/test")
        mock.written.removeAll()

        let payload = Data([0xAA, 0xBB])
        try t.broadcast(packetType: WDCL.tDiscover, data: payload)

        XCTAssertEqual(mock.written.count, 1)
        let raw = mock.written[0]
        // Must be HDLC-framed
        let decoded = HDLC.FrameDecoder()
        let frames  = decoded.feed(raw)
        XCTAssertEqual(frames.count, 1)
        let frame = frames[0]
        // First 4 bytes: WDCL broadcast address
        XCTAssertEqual(Data(frame.prefix(4)), WDCL.broadcast)
        // Byte 4: packet type
        XCTAssertEqual(frame[frame.index(frame.startIndex, offsetBy: 4)], WDCL.tDiscover)
        // Rest: payload
        XCTAssertEqual(Data(frame.dropFirst(5)), payload)
    }

    func testWDCLTransportSendUnicast() throws {
        let mock     = MockWeaveTransport()
        let t        = WDCLTransport(transport: mock)
        try t.open(port: "/dev/test")
        mock.written.removeAll()

        let switchID = Data([0x11, 0x22, 0x33, 0x44])
        let payload  = Data([0xCC, 0xDD])
        try t.send(to: switchID, packetType: WDCL.tCmd, data: payload)

        let raw     = mock.written[0]
        let decoded = HDLC.FrameDecoder()
        let frames  = decoded.feed(raw)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(Data(frames[0].prefix(4)), switchID)
        XCTAssertEqual(frames[0][frames[0].index(frames[0].startIndex, offsetBy: 4)], WDCL.tCmd)
        XCTAssertEqual(Data(frames[0].dropFirst(5)), payload)
    }

    // MARK: - WeaveDevice initial state

    func testWeaveDeviceInitialState() {
        let dev = WeaveDevice()
        XCTAssertNil(dev.switchID)
        XCTAssertNil(dev.endpointID)
        XCTAssertFalse(dev.wdclConnected)
        XCTAssertTrue(dev.endpoints.isEmpty)
        XCTAssertEqual(dev.cpuLoad, 0.0)
        XCTAssertEqual(dev.memTotal, 0)
        XCTAssertEqual(dev.memFree,  0)
        XCTAssertEqual(dev.memUsed,  0)
    }

    // MARK: - WeaveDevice discover sends broadcast

    func testWeaveDeviceDiscover() throws {
        let mock = MockWeaveTransport()
        let t    = WDCLTransport(transport: mock)
        try t.open(port: "/dev/test")
        t.attach(device: WeaveDevice())
        mock.written.removeAll()

        let dev  = WeaveDevice()
        dev.connection = t

        dev.discover()

        XCTAssertEqual(mock.written.count, 1)
        let raw    = mock.written[0]
        let dec    = HDLC.FrameDecoder()
        let frames = dec.feed(raw)
        XCTAssertEqual(frames.count, 1)
        // Destination must be broadcast
        XCTAssertEqual(Data(frames[0].prefix(4)), WDCL.broadcast)
        // Packet type must be DISCOVER
        let typeOffset = frames[0].index(frames[0].startIndex, offsetBy: 4)
        XCTAssertEqual(frames[0][typeOffset], WDCL.tDiscover)
    }

    // MARK: - WeaveDevice handshake

    func testWeaveDeviceHandshake() throws {
        let mock = MockWeaveTransport()
        let t    = WDCLTransport(transport: mock)
        try t.open(port: "/dev/test")

        let dev      = WeaveDevice()
        dev.connection = t
        dev.switchID   = Data([0xAA, 0xBB, 0xCC, 0xDD])  // simulate after discovery

        mock.written.removeAll()
        dev.handshake()

        XCTAssertEqual(mock.written.count, 1)
        let dec    = HDLC.FrameDecoder()
        let frames = dec.feed(mock.written[0])
        XCTAssertEqual(frames.count, 1)

        let frame = frames[0]
        // Destination: dev.switchID
        XCTAssertEqual(Data(frame.prefix(4)), Data([0xAA, 0xBB, 0xCC, 0xDD]))
        // Type: CONNECT
        XCTAssertEqual(frame[frame.index(frame.startIndex, offsetBy: 4)], WDCL.tConnect)
        // Payload: pubkey(32) + signature(64) = 96 bytes
        let payload = Data(frame.dropFirst(5))
        XCTAssertEqual(payload.count, WDCLTransport.pubkeySize + WDCLTransport.signatureLen)
    }

    // MARK: - WeaveDevice sendCommand

    func testWeaveDeviceSendCommand() throws {
        let mock = MockWeaveTransport()
        let t    = WDCLTransport(transport: mock)
        try t.open(port: "/dev/test")

        let dev        = WeaveDevice()
        dev.connection = t
        dev.switchID   = Data([0x01, 0x02, 0x03, 0x04])

        mock.written.removeAll()
        dev.sendCommand(command: WeaveCmd.endpointsList, data: Data())

        let dec    = HDLC.FrameDecoder()
        let frames = dec.feed(mock.written[0])
        XCTAssertEqual(frames.count, 1)

        let frame = frames[0]
        // Type: CMD
        XCTAssertEqual(frame[frame.index(frame.startIndex, offsetBy: 4)], WDCL.tCmd)
        // First two payload bytes: command code big-endian
        let payloadStart = frame.index(frame.startIndex, offsetBy: 5)
        let cmdHi = frame[payloadStart]
        let cmdLo = frame[frame.index(payloadStart, offsetBy: 1)]
        let cmd   = UInt16(cmdHi) << 8 | UInt16(cmdLo)
        XCTAssertEqual(cmd, WeaveCmd.endpointsList)
    }

    // MARK: - WeaveDevice log handler

    func testHandleLogWdclConnection() {
        let dev  = WeaveDevice()
        XCTAssertFalse(dev.wdclConnected)
        dev.handleLog(WeaveLogFrame(timestamp: 0, level: 0,
                                    event: WeaveEvt.etProtocolWdclConnection, data: Data()))
        XCTAssertTrue(dev.wdclConnected)
    }

    func testHandleLogHostEndpoint() {
        let dev      = WeaveDevice()
        let epID     = Data(repeating: 0xDE, count: 8)
        dev.handleLog(WeaveLogFrame(timestamp: 0, level: 0,
                                    event: WeaveEvt.etProtocolWdclHostEndpoint, data: epID))
        XCTAssertEqual(dev.endpointID, epID)
    }

    func testHandleLogHostEndpointWrongLength() {
        let dev   = WeaveDevice()
        let epID  = Data(repeating: 0xDE, count: 5)  // wrong length
        dev.handleLog(WeaveLogFrame(timestamp: 0, level: 0,
                                    event: WeaveEvt.etProtocolWdclHostEndpoint, data: epID))
        XCTAssertNil(dev.endpointID)  // should be ignored
    }

    func testHandleLogEpAlive() {
        let dev  = WeaveDevice()
        let epID = Data(repeating: 0x7F, count: 8)
        dev.handleLog(WeaveLogFrame(timestamp: 0, level: 0,
                                    event: WeaveEvt.etProtocolWeaveEpAlive, data: epID))
        XCTAssertNotNil(dev.endpoints[epID])
    }

    func testHandleLogEpVia() {
        let dev    = WeaveDevice()
        let epID   = Data(repeating: 0x01, count: 8)
        let swID   = Data(repeating: 0x02, count: 4)
        // EpAlive must come first so the endpoint exists in the registry
        dev.handleLog(WeaveLogFrame(timestamp: 0, level: 0,
                                    event: WeaveEvt.etProtocolWeaveEpAlive, data: epID))
        var payload = epID; payload.append(swID)
        dev.handleLog(WeaveLogFrame(timestamp: 0, level: 0,
                                    event: WeaveEvt.etProtocolWeaveEpVia, data: payload))
        XCTAssertEqual(dev.endpoints[epID]?.viaSwitchID, swID)
    }

    func testHandleLogCpuStat() {
        let dev = WeaveDevice()
        dev.handleLog(WeaveLogFrame(timestamp: 0, level: 0,
                                    event: WeaveEvt.etStatCpu, data: Data([42])))
        XCTAssertEqual(dev.cpuLoad, 42.0)
    }

    func testHandleLogMemoryStat() {
        let dev  = WeaveDevice()
        // memFree = 0x0000_0100 = 256, memTotal = 0x0000_0400 = 1024
        let data = Data([0, 0, 1, 0,  0, 0, 4, 0])
        dev.handleLog(WeaveLogFrame(timestamp: 0, level: 0,
                                    event: WeaveEvt.etStatMemory, data: data))
        XCTAssertEqual(dev.memFree,  256)
        XCTAssertEqual(dev.memTotal, 1024)
        XCTAssertEqual(dev.memUsed,  768)
    }

    func testHandleLogMemoryStatTooShort() {
        let dev  = WeaveDevice()
        dev.handleLog(WeaveLogFrame(timestamp: 0, level: 0,
                                    event: WeaveEvt.etStatMemory, data: Data([0, 0, 1])))
        XCTAssertEqual(dev.memFree, 0)   // untouched
    }

    // MARK: - WeaveDevice incomingFrame — LOG dispatch

    func testIncomingFrameLogDispatch() throws {
        let mock = MockWeaveTransport()
        let t    = WDCLTransport(transport: mock)
        try t.open(port: "/dev/test")

        let dev        = WeaveDevice()
        dev.connection = t
        let fakeSwitchID = Data([0x01, 0x02, 0x03, 0x04])
        dev.switchID   = fakeSwitchID

        // Build a raw WDCL frame: switch_id + WDCL_T_LOG + payload
        // Payload layout: type(1) + ts(4) + level(1) + evt_hi(1) + evt_lo(1) = 8 bytes min
        // We'll use event = etProtocolWdclConnection (0x3002)
        let logPayload = Data([
            0x00,                    // [0] type byte
            0x00, 0x00, 0x00, 0x00, // [1..4] timestamp (4 bytes)
            0x01,                    // [5] level
            0x30, 0x02               // [6..7] event: 0x3002
        ])
        var frame = fakeSwitchID
        frame.append(WDCL.tLog)
        frame.append(logPayload)

        XCTAssertFalse(dev.wdclConnected)
        dev.incomingFrame(frame)
        XCTAssertTrue(dev.wdclConnected)
    }

    // MARK: - WeaveDevice incomingFrame — ENDPOINT_PKT dispatch

    func testIncomingFrameEndpointPkt() throws {
        let mock = MockWeaveTransport()
        let t    = WDCLTransport(transport: mock)
        try t.open(port: "/dev/test")

        let dev        = WeaveDevice()
        dev.connection = t
        dev.switchID   = t.switchID   // device's switchID = our host's switchID

        var receivedData: Data?
        var receivedSrc:  Data?

        let parent = WeaveInterface(name: "test-weave", port: "/dev/null",
                                    transport: MockWeaveTransport())
        dev.rnsInterface = parent
        parent.onPeerAdded = { peer in
            peer.rawInboundHandler = { data, _ in
                receivedData = data
                receivedSrc  = peer.endpointAddr
            }
        }
        try parent.start()

        // Build: dst_switch_id(4) + ENDPOINT_PKT(1) + rns_data + src_endpoint_id(8)
        let rnsData  = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let srcEpID  = Data(repeating: 0xAB, count: 8)
        var payload  = rnsData; payload.append(srcEpID)

        var wdclFrame = t.switchID   // dst = our switch_id (from transport)
        wdclFrame.append(WDCL.tEndpointPkt)
        wdclFrame.append(payload)

        dev.incomingFrame(wdclFrame)

        XCTAssertEqual(receivedData, rnsData)
        XCTAssertEqual(receivedSrc,  srcEpID)
    }

    // MARK: - WeaveDevice incomingFrame — short frame ignored

    func testIncomingFrameTooShort() {
        let dev    = WeaveDevice()
        let mock   = MockWeaveTransport()
        let t      = WDCLTransport(transport: mock)
        dev.connection = t
        // Only 4 bytes — not enough (need > switchIDLen + 1 = 5)
        dev.incomingFrame(Data([0x01, 0x02, 0x03, 0x04]))
        // Should not crash or change state
        XCTAssertNil(dev.switchID)
    }

    // MARK: - WeaveInterface lifecycle

    func testWeaveInterfaceInit() {
        let iface = WeaveInterface(name: "W0", port: "/dev/test",
                                   transport: MockWeaveTransport())
        XCTAssertEqual(iface.name, "W0")
        XCTAssertEqual(iface.port, "/dev/test")
        XCTAssertFalse(iface.isOnline)
        XCTAssertEqual(iface.bitrate, WeaveInterface.bitrateGuess)
        XCTAssertEqual(iface.hwMtu, WeaveInterface.hwMtuValue)
    }

    func testWeaveInterfaceStartStop() throws {
        let mock  = MockWeaveTransport()
        let iface = WeaveInterface(name: "W0", port: "/dev/test", transport: mock)
        XCTAssertFalse(iface.isOnline)
        try iface.start()
        XCTAssertTrue(iface.isOnline)
        XCTAssertTrue(mock.openCalled)
        iface.stop()
        XCTAssertFalse(iface.isOnline)
        XCTAssertTrue(mock.closeCalled)
    }

    func testWeaveInterfaceStartSendsDiscover() throws {
        let mock  = MockWeaveTransport()
        let iface = WeaveInterface(name: "W0", port: "/dev/test", transport: mock)
        try iface.start()

        // start() calls device.discover() which broadcasts a WDCL_T_DISCOVER frame
        XCTAssertFalse(mock.written.isEmpty)
        let dec    = HDLC.FrameDecoder()
        let frames = dec.feed(mock.written.last!)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(Data(frames[0].prefix(4)), WDCL.broadcast)
    }

    // MARK: - WeaveInterface peer management

    func testAddPeerAndPeerCount() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        XCTAssertEqual(iface.peerCount, 0)

        let epID = Data(repeating: 0x01, count: 8)
        iface.addPeer(endpointAddr: epID)

        XCTAssertEqual(iface.peerCount, 1)
        XCTAssertNotNil(iface.spawnedInterfaces[epID])
        XCTAssertNotNil(iface.peers[epID])
    }

    func testAddPeerCallsOnPeerAdded() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        var addedPeer: WeaveInterfacePeer?
        iface.onPeerAdded = { p in addedPeer = p }

        let epID = Data(repeating: 0x02, count: 8)
        iface.addPeer(endpointAddr: epID)

        XCTAssertNotNil(addedPeer)
        XCTAssertEqual(addedPeer?.endpointAddr, epID)
    }

    func testAddPeerIdempotent() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        var callCount = 0
        iface.onPeerAdded = { _ in callCount += 1 }

        let epID = Data(repeating: 0x03, count: 8)
        iface.addPeer(endpointAddr: epID)
        iface.addPeer(endpointAddr: epID)  // second call — should not add again

        XCTAssertEqual(iface.peerCount, 1)
        XCTAssertEqual(callCount, 1)
    }

    func testRefreshPeer() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let epID = Data(repeating: 0x04, count: 8)
        iface.addPeer(endpointAddr: epID)

        // Back-date lastSeen by 5 seconds
        let before = iface.peers[epID]!.lastSeen
        Thread.sleep(forTimeInterval: 0.01)
        iface.refreshPeer(endpointAddr: epID)
        let after  = iface.peers[epID]!.lastSeen

        XCTAssertTrue(after > before)
    }

    func testEndpointVia() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let epID = Data(repeating: 0x05, count: 8)
        let swID = Data([0xA1, 0xB2, 0xC3, 0xD4])
        iface.addPeer(endpointAddr: epID)
        iface.endpointVia(endpointAddr: epID, viaSwitchID: swID)

        XCTAssertEqual(iface.spawnedInterfaces[epID]?.viaSwitchID, swID)
    }

    // MARK: - WeaveInterface peerJobs timeout

    func testPeerJobsTimesOutStalePeer() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        var removedPeer: WeaveInterfacePeer?
        iface.onPeerRemoved = { p in removedPeer = p }

        let epID = Data(repeating: 0x06, count: 8)
        iface.addPeer(endpointAddr: epID)

        // Manually back-date lastSeen beyond the timeout
        iface.peers[epID]?.lastSeen = Date(timeIntervalSinceNow: -(WeaveInterface.peeringTimeout + 1))

        iface.peerJobs()

        XCTAssertEqual(iface.peerCount, 0)
        XCTAssertNotNil(removedPeer)
    }

    func testPeerJobsKeepsFreshPeer() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        var removed = false
        iface.onPeerRemoved = { _ in removed = true }

        let epID = Data(repeating: 0x07, count: 8)
        iface.addPeer(endpointAddr: epID)

        iface.peerJobs()  // peer is fresh — should NOT be removed

        XCTAssertEqual(iface.peerCount, 1)
        XCTAssertFalse(removed)
    }

    // MARK: - WeaveInterface processIncoming routes to peer

    func testProcessIncomingRoutesToPeer() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let epID = Data(repeating: 0x08, count: 8)
        iface.addPeer(endpointAddr: epID)

        var received: Data?
        iface.spawnedInterfaces[epID]?.rawInboundHandler = { data, _ in received = data }

        let pkt = Data([0x11, 0x22, 0x33])
        iface.processIncoming(data: pkt, endpointAddr: epID)

        XCTAssertEqual(received, pkt)
    }

    func testProcessIncomingIgnoresUnknownPeer() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let unknown = Data(repeating: 0xFF, count: 8)
        // Should not crash
        iface.processIncoming(data: Data([0x01]), endpointAddr: unknown)
    }

    // MARK: - WeaveInterfacePeer name

    func testWeaveInterfacePeerName() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let epID = Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89])
        iface.addPeer(endpointAddr: epID)

        let peer = iface.spawnedInterfaces[epID]!
        XCTAssertTrue(peer.name.hasPrefix("WeaveInterfacePeer["))
        XCTAssertTrue(peer.name.contains("abcdef0123456789"))
    }

    // MARK: - WeaveInterfacePeer outgoing (processOutgoing)

    func testWeaveInterfacePeerOutgoing() throws {
        let mock  = MockWeaveTransport()
        let iface = WeaveInterface(name: "W0", port: "/dev/test", transport: mock)
        try iface.start()

        let epID = Data(repeating: 0x09, count: 8)
        iface.addPeer(endpointAddr: epID)
        let peer = iface.spawnedInterfaces[epID]!

        // Pre-set device.switchID so deliverPacket → sendCommand doesn't bail out
        iface.device.switchID = Data([0xA1, 0xB1, 0xC1, 0xD1])
        mock.written.removeAll()
        let payload = Data([0xAA, 0xBB, 0xCC])
        peer.processOutgoing(payload)

        // At least one HDLC-framed packet should have been written
        XCTAssertFalse(mock.written.isEmpty)

        // Peer and parent tx stats incremented
        XCTAssertEqual(peer.txBytes,   payload.count)
        XCTAssertEqual(peer.txPackets, 1)
        XCTAssertEqual(iface.txBytes,  payload.count)
    }

    // MARK: - WeaveInterfacePeer duplicate suppression

    func testDuplicateSuppression() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let epID = Data(repeating: 0x0A, count: 8)
        iface.addPeer(endpointAddr: epID)
        let peer = iface.spawnedInterfaces[epID]!

        var deliveries = 0
        peer.rawInboundHandler = { _, _ in deliveries += 1 }

        let pkt = Data([0x01, 0x02, 0x03])
        peer.processIncoming(data: pkt, endpointAddr: epID)  // first — delivered
        peer.processIncoming(data: pkt, endpointAddr: epID)  // duplicate — dropped
        peer.processIncoming(data: pkt, endpointAddr: epID)  // duplicate — dropped

        XCTAssertEqual(deliveries, 1)
    }

    func testDifferentPacketsNotSuppressed() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let epID = Data(repeating: 0x0B, count: 8)
        iface.addPeer(endpointAddr: epID)
        let peer = iface.spawnedInterfaces[epID]!

        var deliveries = 0
        peer.rawInboundHandler = { _, _ in deliveries += 1 }

        peer.processIncoming(data: Data([0x01]), endpointAddr: epID)
        peer.processIncoming(data: Data([0x02]), endpointAddr: epID)
        peer.processIncoming(data: Data([0x03]), endpointAddr: epID)

        XCTAssertEqual(deliveries, 3)
    }

    func testDedupDequeMaxLength() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let epID = Data(repeating: 0x0C, count: 8)
        iface.addPeer(endpointAddr: epID)
        let peer = iface.spawnedInterfaces[epID]!
        peer.rawInboundHandler = { _, _ in }

        // Send maxLen+1 unique packets to exercise the pruning path
        for i in 0 ..< (WeaveInterface.multiIfDequeLen + 2) {
            peer.processIncoming(data: Data([UInt8(i & 0xFF), UInt8(i >> 8)]),
                                 endpointAddr: epID)
        }

        // Deque should be bounded
        XCTAssertLessThanOrEqual(iface.mifDeque.count, WeaveInterface.multiIfDequeLen)
    }

    // MARK: - WeaveInterfacePeer incoming stats

    func testPeerIncomingStats() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let epID = Data(repeating: 0x0D, count: 8)
        iface.addPeer(endpointAddr: epID)
        let peer = iface.spawnedInterfaces[epID]!
        peer.rawInboundHandler = { _, _ in }

        let pkt = Data(repeating: 0x55, count: 16)
        peer.processIncoming(data: pkt, endpointAddr: epID)

        XCTAssertEqual(peer.rxBytes,   16)
        XCTAssertEqual(peer.rxPackets, 1)
        XCTAssertEqual(iface.rxBytes,  16)
    }

    // MARK: - WeaveInterfacePeer teardown

    func testTeardown() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let epID = Data(repeating: 0x0E, count: 8)
        iface.addPeer(endpointAddr: epID)

        XCTAssertEqual(iface.peerCount, 1)
        iface.spawnedInterfaces[epID]!.teardown()
        XCTAssertEqual(iface.peerCount, 0)
        XCTAssertTrue(iface.peers.isEmpty)
    }

    // MARK: - WeaveInterfacePeer hwMtu inherits from parent

    func testPeerHwMtu() throws {
        let iface = WeaveInterface(name: "W0", port: "/dev/null",
                                   transport: MockWeaveTransport())
        try iface.start()

        let epID = Data(repeating: 0x0F, count: 8)
        iface.addPeer(endpointAddr: epID)
        let peer = iface.spawnedInterfaces[epID]!

        XCTAssertEqual(peer.hwMtu, WeaveInterface.hwMtuValue)
    }

    // MARK: - WeaveInterfacePeer send(_ packet:) interface conformance

    func testPeerSendInterface() throws {
        let mock  = MockWeaveTransport()
        let iface = WeaveInterface(name: "W0", port: "/dev/test", transport: mock)
        try iface.start()

        let epID = Data(repeating: 0x10, count: 8)
        iface.addPeer(endpointAddr: epID)
        let peer = iface.spawnedInterfaces[epID]!

        // send() should not throw and should result in a write.
        // Pre-set device.switchID so sendCommand doesn't bail out early.
        iface.device.switchID = Data([0xA0, 0xB0, 0xC0, 0xD0])
        mock.written.removeAll()
        let pkt = Packet(destinationType: .single, packetType: .data,
                         destinationHash: Data(repeating: 0x00, count: 16),
                         data: Data([0x01, 0x02, 0x03]))
        XCTAssertNoThrow(try peer.send(pkt))
        XCTAssertFalse(mock.written.isEmpty)
    }

    // MARK: - WeaveInterface conforms to Interface protocol

    func testWeaveInterfaceConformsToInterface() throws {
        let iface: any Interface = WeaveInterface(name: "W0", port: "/dev/null",
                                                   transport: MockWeaveTransport())
        XCTAssertFalse(iface.isOnline)
        XCTAssertEqual(iface.bitrate, WeaveInterface.bitrateGuess)
        XCTAssertEqual(iface.hwMtu, WeaveInterface.hwMtuValue)
        XCTAssertNil(iface.rssi)
        XCTAssertNil(iface.snr)
        XCTAssertNil(iface.quality)
    }
}
