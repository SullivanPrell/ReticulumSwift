import XCTest
@testable import ReticulumSwift

// MARK: - Mock daemon (no real i2pd needed in tests)

final class MockI2PDaemon: I2PDaemonProtocol {
    var samPort: Int = 7656
    var startCallCount  = 0
    var stopCallCount   = 0
    var lastDataDir: URL?
    var shouldThrow     = false

    func start(dataDirectory: URL) throws {
        startCallCount += 1
        lastDataDir = dataDirectory
        if shouldThrow { throw I2PDaemonError.startFailed("mock error") }
    }
    func stop() { stopCallCount += 1 }
}

// MARK: - I2PInterface constants

final class I2PInterfaceConstantsTests: XCTestCase {

    func testBitrateGuess() {
        XCTAssertEqual(I2PInterface.bitrateGuess, 256_000,
                       "Python: BITRATE_GUESS = 256*1000")
    }

    func testDefaultIfacSize() {
        XCTAssertEqual(I2PInterface.defaultIfacSize, 16,
                       "Python: DEFAULT_IFAC_SIZE = 16")
    }

    func testHwMtu() {
        XCTAssertEqual(I2PInterface.hwMtu, 1064,
                       "Python: self.HW_MTU = 1064")
    }
}

// MARK: - I2PInterfacePeer constants

final class I2PInterfacePeerConstantsTests: XCTestCase {

    func testReconnectWait() {
        XCTAssertEqual(I2PInterfacePeer.reconnectWait, 15,
                       "Python: RECONNECT_WAIT = 15")
    }

    func testReconnectMaxTriesIsNil() {
        XCTAssertNil(I2PInterfacePeer.reconnectMaxTries,
                     "Python: RECONNECT_MAX_TRIES = None (unlimited)")
    }

    func testI2PUserTimeout() {
        XCTAssertEqual(I2PInterfacePeer.i2pUserTimeout, 45,
                       "Python: I2P_USER_TIMEOUT = 45")
    }

    func testI2PProbeAfter() {
        XCTAssertEqual(I2PInterfacePeer.i2pProbeAfter, 10,
                       "Python: I2P_PROBE_AFTER = 10")
    }

    func testI2PProbeInterval() {
        XCTAssertEqual(I2PInterfacePeer.i2pProbeInterval, 9,
                       "Python: I2P_PROBE_INTERVAL = 9")
    }

    func testI2PProbes() {
        XCTAssertEqual(I2PInterfacePeer.i2pProbes, 5,
                       "Python: I2P_PROBES = 5")
    }

    func testI2PReadTimeout() {
        let expected = (I2PInterfacePeer.i2pProbeInterval * I2PInterfacePeer.i2pProbes
                        + I2PInterfacePeer.i2pProbeAfter) * 2
        XCTAssertEqual(I2PInterfacePeer.i2pReadTimeout, expected,
                       "Python: I2P_READ_TIMEOUT = (PROBE_INTERVAL*PROBES + PROBE_AFTER)*2")
    }

    func testTunnelStateValues() {
        XCTAssertEqual(I2PInterfacePeer.TunnelState.initializing.rawValue, 0x00,
                       "Python: TUNNEL_STATE_INIT = 0x00")
        XCTAssertEqual(I2PInterfacePeer.TunnelState.active.rawValue, 0x01,
                       "Python: TUNNEL_STATE_ACTIVE = 0x01")
        XCTAssertEqual(I2PInterfacePeer.TunnelState.stale.rawValue, 0x02,
                       "Python: TUNNEL_STATE_STALE = 0x02")
    }
}

// MARK: - I2PDaemonProtocol / MockI2PDaemon

final class I2PDaemonProtocolTests: XCTestCase {

    func testDefaultSAMPort() {
        let daemon = MockI2PDaemon()
        XCTAssertEqual(daemon.samPort, 7656,
                       "Default SAM port is 7656")
    }

    func testStartCallForwarded() throws {
        let daemon = MockI2PDaemon()
        let url = URL(fileURLWithPath: "/tmp/i2p_test")
        try daemon.start(dataDirectory: url)
        XCTAssertEqual(daemon.startCallCount, 1)
        XCTAssertEqual(daemon.lastDataDir, url)
    }

    func testStopCallForwarded() {
        let daemon = MockI2PDaemon()
        daemon.stop()
        XCTAssertEqual(daemon.stopCallCount, 1)
    }

    func testStartThrowsOnError() {
        let daemon = MockI2PDaemon()
        daemon.shouldThrow = true
        XCTAssertThrowsError(try daemon.start(dataDirectory: URL(fileURLWithPath: "/tmp")))
    }
}

// MARK: - SAMClient line formatting

final class SAMClientLineTests: XCTestCase {

    func testHelloLine() {
        XCTAssertEqual(SAMClient.helloLine,
                       "HELLO VERSION MIN=3.1 MAX=3.1\n",
                       "SAM 3.1 handshake line")
    }

    func testSessionCreateLine() {
        let line = SAMClient.sessionCreateLine(sessionID: "abc123")
        XCTAssertTrue(line.hasPrefix("SESSION CREATE STYLE=STREAM ID=abc123 DESTINATION=TRANSIENT"))
        XCTAssertTrue(line.hasSuffix("\n"))
    }

    func testStreamConnectLine() {
        let line = SAMClient.streamConnectLine(sessionID: "abc123", destination: "xxx.b32.i2p")
        XCTAssertTrue(line.hasPrefix("STREAM CONNECT ID=abc123 DESTINATION=xxx.b32.i2p"))
        XCTAssertTrue(line.hasSuffix("\n"))
    }

    func testStreamAcceptLine() {
        let line = SAMClient.streamAcceptLine(sessionID: "abc123")
        XCTAssertTrue(line.hasPrefix("STREAM ACCEPT ID=abc123"))
        XCTAssertTrue(line.hasSuffix("\n"))
    }
}

// MARK: - SAMClient response parsing

final class SAMClientParsingTests: XCTestCase {

    func testParseHelloReplyOK() {
        let reply = "HELLO REPLY RESULT=OK VERSION=3.1\n"
        let result = SAMClient.parseHelloReply(reply)
        XCTAssertEqual(result, .ok("3.1"))
    }

    func testParseHelloReplyFailed() {
        let reply = "HELLO REPLY RESULT=NOVERSION\n"
        let result = SAMClient.parseHelloReply(reply)
        if case .failure(let reason) = result {
            XCTAssertTrue(reason.contains("NOVERSION"))
        } else {
            XCTFail("Expected failure, got \(result)")
        }
    }

    func testParseSessionStatusOK() {
        let reply = "SESSION STATUS RESULT=OK DESTINATION=AAECAw==\n"
        let result = SAMClient.parseSessionStatus(reply)
        XCTAssertEqual(result, .ok("AAECAw=="))
    }

    func testParseSessionStatusFailed() {
        let reply = "SESSION STATUS RESULT=DUPLICATED_ID\n"
        let result = SAMClient.parseSessionStatus(reply)
        if case .failure(let reason) = result {
            XCTAssertTrue(reason.contains("DUPLICATED_ID"))
        } else {
            XCTFail("Expected failure, got \(result)")
        }
    }

    func testParseStreamStatusOK() {
        let reply = "STREAM STATUS RESULT=OK\n"
        let result = SAMClient.parseStreamStatus(reply)
        XCTAssertEqual(result, .ok)
    }

    func testParseStreamStatusFailed() {
        let reply = "STREAM STATUS RESULT=CANT_REACH_PEER\n"
        let result = SAMClient.parseStreamStatus(reply)
        if case .failure(let reason) = result {
            XCTAssertTrue(reason.contains("CANT_REACH_PEER"))
        } else {
            XCTFail("Expected failure, got \(result)")
        }
    }

    func testExtractSAMValue() {
        let line = "HELLO REPLY RESULT=OK VERSION=3.1"
        XCTAssertEqual(SAMClient.extractValue(for: "RESULT", in: line), "OK")
        XCTAssertEqual(SAMClient.extractValue(for: "VERSION", in: line), "3.1")
        XCTAssertNil(SAMClient.extractValue(for: "NOPE", in: line))
    }
}

// MARK: - I2PInterface init

final class I2PInterfaceInitTests: XCTestCase {

    func testInterfaceStartsOffline() {
        let daemon = MockI2PDaemon()
        let iface = I2PInterface(name: "TestI2P", daemon: daemon,
                                 dataDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertFalse(iface.isOnline, "Interface must start offline")
    }

    func testInterfaceHasCorrectName() {
        let daemon = MockI2PDaemon()
        let iface = I2PInterface(name: "TestI2P", daemon: daemon,
                                 dataDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(iface.name, "TestI2P")
    }

    func testInterfaceBitrate() {
        let daemon = MockI2PDaemon()
        let iface = I2PInterface(name: "TestI2P", daemon: daemon,
                                 dataDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(iface.bitrate, I2PInterface.bitrateGuess)
    }

    func testInterfaceConnectableDefaultFalse() {
        let daemon = MockI2PDaemon()
        let iface = I2PInterface(name: "TestI2P", daemon: daemon,
                                 dataDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertFalse(iface.connectable,
                       "Python: connectable = False (default)")
    }

    func testInterfaceSpawnedInterfacesEmpty() {
        let daemon = MockI2PDaemon()
        let iface = I2PInterface(name: "TestI2P", daemon: daemon,
                                 dataDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(iface.clients, 0,
                       "Python: clients property = len(spawned_interfaces)")
    }

    func testInterfaceI2PTunneled() {
        let daemon = MockI2PDaemon()
        let iface = I2PInterface(name: "TestI2P", daemon: daemon,
                                 dataDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(iface.i2pTunneled,
                      "Python: self.i2p_tunneled = True")
    }

    func testInterfaceSupportDiscovery() {
        let daemon = MockI2PDaemon()
        let iface = I2PInterface(name: "TestI2P", daemon: daemon,
                                 dataDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(iface.supportsDiscovery,
                      "Python: self.supports_discovery = True")
    }
}

// MARK: - I2PInterfacePeer init

final class I2PInterfacePeerInitTests: XCTestCase {

    func testPeerStartsOffline() {
        let peer = I2PInterfacePeer(name: "Test Peer",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: nil)
        XCTAssertFalse(peer.online, "Peer must start offline, awaiting tunnel")
    }

    func testPeerInitiatorFlagSetForOutbound() {
        let peer = I2PInterfacePeer(name: "Test Peer",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: nil)
        XCTAssertTrue(peer.initiator, "Outbound peers are initiators")
    }

    func testPeerKissFramingDefaultFalse() {
        let peer = I2PInterfacePeer(name: "Test Peer",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: nil)
        XCTAssertFalse(peer.kissFraming,
                       "Python: self.kiss_framing = False (I2P uses HDLC)")
    }

    func testPeerTunnelStateStartsInit() {
        let peer = I2PInterfacePeer(name: "Test Peer",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: nil)
        XCTAssertEqual(peer.tunnelState, .initializing,
                       "Python: TUNNEL_STATE_INIT")
    }

    func testPeerI2PTunneled() {
        let peer = I2PInterfacePeer(name: "Test Peer",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: nil)
        XCTAssertTrue(peer.i2pTunneled,
                      "Python: self.i2p_tunneled = True")
    }

    func testPeerHWMTU() {
        let peer = I2PInterfacePeer(name: "Test Peer",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: nil)
        XCTAssertEqual(peer.hwMtu, I2PInterface.hwMtu,
                       "Python: self.HW_MTU = 1064")
    }
}

// MARK: - I2PInterfacePeer HDLC framing

final class I2PInterfacePeerHDLCTests: XCTestCase {

    func testOutgoingFramedWithHDLC() {
        let peer = I2PInterfacePeer(name: "Test Peer",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: nil)
        let data = Data([0x01, 0x02, 0x7E, 0x03])  // contains HDLC.FLAG
        let framed = peer.hdlcFrame(data)

        XCTAssertEqual(framed.first, HDLC.flag, "Must start with HDLC flag")
        XCTAssertEqual(framed.last,  HDLC.flag, "Must end with HDLC flag")
    }

    func testOutgoingEscapesFlagBytes() {
        let peer = I2PInterfacePeer(name: "Test Peer",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: nil)
        let data = Data([HDLC.flag])          // raw 0x7E inside payload
        let framed = peer.hdlcFrame(data)

        // Format: FLAG | ESC (0x5E) | FLAG^0x20 (0x5E) | FLAG
        // The inner 0x7E must be escaped to [0x7D, 0x5E]
        XCTAssertGreaterThan(framed.count, 3, "Escaped flag adds bytes")
        let inner = framed.dropFirst().dropLast()
        XCTAssertFalse(inner.contains(HDLC.flag),
                       "No bare FLAG bytes in escaped payload")
    }

    func testIncomingHDLCUnframes() {
        let peer = I2PInterfacePeer(name: "Test Peer",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: nil)
        let original = Data([0x01, 0x02, 0x03])
        let framed   = peer.hdlcFrame(original)

        var received: [Data] = []
        peer.feedBytes(framed) { received.append($0) }

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0], original)
    }

    func testIncomingMultipleFrames() {
        let peer = I2PInterfacePeer(name: "Test Peer",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: nil)
        let f1 = peer.hdlcFrame(Data([0xAA]))
        let f2 = peer.hdlcFrame(Data([0xBB]))
        let combined = f1 + f2

        var received: [Data] = []
        peer.feedBytes(combined) { received.append($0) }

        XCTAssertEqual(received.count, 2)
    }
}

// MARK: - I2PInterface peer management

final class I2PInterfacePeerManagementTests: XCTestCase {

    func testAddPeerIncreasesClientCount() {
        let daemon = MockI2PDaemon()
        let iface = I2PInterface(name: "TestI2P", daemon: daemon,
                                 dataDirectory: URL(fileURLWithPath: "/tmp"))
        let peer = I2PInterfacePeer(name: "peer1",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: iface)
        iface.addSpawnedInterface(peer)
        XCTAssertEqual(iface.clients, 1)
    }

    func testRemovePeerDecreasesClientCount() {
        let daemon = MockI2PDaemon()
        let iface = I2PInterface(name: "TestI2P", daemon: daemon,
                                 dataDirectory: URL(fileURLWithPath: "/tmp"))
        let peer = I2PInterfacePeer(name: "peer1",
                                    targetI2PDestination: "abc.b32.i2p",
                                    parentInterface: iface)
        iface.addSpawnedInterface(peer)
        iface.removeSpawnedInterface(peer)
        XCTAssertEqual(iface.clients, 0)
    }
}

// MARK: - I2PDaemon (embedded, requires CI2PD)

final class I2PDaemonTests: XCTestCase {

    func testDefaultSAMPort() {
        let daemon = I2PDaemon()
        XCTAssertEqual(daemon.samPort, 7656,
                       "Default SAM port is 7656 (i2pd sam.port default)")
    }

    func testCustomSAMPort() {
        let daemon = I2PDaemon(samPort: 7700)
        XCTAssertEqual(daemon.samPort, 7700)
    }

    func testIsNotRunningBeforeStart() {
        let daemon = I2PDaemon()
        XCTAssertFalse(daemon.isRunning, "Daemon must not be running before start()")
    }

    func testDoubleStopIsNoop() {
        let daemon = I2PDaemon()
        daemon.stop()   // stop when not running — must not crash
        daemon.stop()
    }
}
