import XCTest
@testable import ReticulumSwift

/// Tests for BackboneInterface — the high-bandwidth TCP backbone interface.
///
/// Python reference (BackboneInterface.py — BackboneClientInterface):
///   HW_MTU             = 1_048_576   (1 MB, vs 262144 for TCPClientInterface)
///   BITRATE_GUESS      = 100_000_000 (100 Mbps)
///   AUTOCONFIGURE_MTU  = True
///   RECONNECT_WAIT     = 5           (seconds between reconnect attempts)
///   RECONNECT_MAX_TRIES = None       (infinite by default)
///
/// BackboneInterface uses the same HDLC framing as TCPClientInterface.
final class BackboneInterfaceTests: XCTestCase {

    // MARK: - Constants

    func testHwMtuIs1MB() {
        let iface = BackboneInterface(name: "test-bb", host: "127.0.0.1", port: 4242)
        XCTAssertEqual(iface.hwMtu, 1_048_576,
                       "BackboneInterface HW_MTU must be 1 MB (Python BackboneClientInterface.HW_MTU)")
    }

    func testBitrateGuessIs100Mbps() {
        let iface = BackboneInterface(name: "test-bb", host: "127.0.0.1", port: 4242)
        XCTAssertEqual(iface.bitrate, 100_000_000,
                       "BackboneInterface BITRATE_GUESS must be 100 Mbps")
    }

    func testAutoconfigureMtuIsTrue() {
        let iface = BackboneInterface(name: "test-bb", host: "127.0.0.1", port: 4242)
        XCTAssertTrue(iface.autoconfigureMtu,
                      "BackboneInterface AUTOCONFIGURE_MTU must be true")
    }

    func testReconnectWaitIs5Seconds() {
        let iface = BackboneInterface(name: "test-bb", host: "127.0.0.1", port: 4242)
        XCTAssertEqual(iface.reconnectWait, 5.0,
                       "RECONNECT_WAIT must be 5 seconds")
    }

    // MARK: - Interface protocol conformance

    func testNameIsSet() {
        let iface = BackboneInterface(name: "backbone0", host: "10.0.0.1", port: 5000)
        XCTAssertEqual(iface.name, "backbone0")
    }

    func testHostAndPortAreSet() {
        let iface = BackboneInterface(name: "bb", host: "192.168.1.1", port: 9999)
        XCTAssertEqual(iface.host, "192.168.1.1")
        XCTAssertEqual(iface.port, 9999)
    }

    func testIsOfflineBeforeStart() {
        let iface = BackboneInterface(name: "bb", host: "127.0.0.1", port: 4242)
        XCTAssertFalse(iface.isOnline, "BackboneInterface must be offline before start()")
    }

    func testDefaultModeIsFull() {
        let iface = BackboneInterface(name: "bb", host: "127.0.0.1", port: 4242)
        XCTAssertEqual(iface.mode, .full,
                       "BackboneInterface default mode must be .full (Python MODE_FULL)")
    }

    func testStopWhenNotStartedIsNoOp() {
        let iface = BackboneInterface(name: "bb", host: "127.0.0.1", port: 4242)
        iface.stop()  // must not crash
    }

    // MARK: - HDLC framing (same format as TCPClientInterface)

    func testHdlcFrameRoundTrip() {
        let original = Data([0x01, 0x00, 0xAA, 0xBB, 0xCC])
        let framed = HDLC.frame(original)
        let decoder = HDLC.FrameDecoder()
        let decoded = decoder.feed(framed)
        XCTAssertEqual(decoded.count, 1, "HDLC frame round-trip must produce exactly one frame")
        XCTAssertEqual(decoded[0], original, "HDLC decoded frame must match original data")
    }

    func testHdlcEscapingFor0x7E() {
        // FLAG byte (0x7E) inside data must be escaped
        let payload = Data([0x7E, 0x01, 0x7E])
        let framed = HDLC.frame(payload)
        // Framed: FLAG escaped-FLAG 0x01 escaped-FLAG FLAG
        XCTAssertFalse(framed.dropFirst().dropLast().contains(0x7E),
                       "HDLC framing must escape 0x7E bytes inside the payload")
    }

    func testHdlcEscapingFor0x7D() {
        // ESC byte (0x7D) inside data must be escaped
        let payload = Data([0x7D, 0xAA])
        let framed = HDLC.frame(payload)
        let inner = Data(framed.dropFirst().dropLast()) // remove FLAG delimiters
        // Inner should NOT contain 0x7D followed by 0xAA directly
        var found = false
        for i in 0..<(inner.count - 1) {
            if inner[i] == 0x7D && inner[i+1] == 0xAA { found = true }
        }
        XCTAssertFalse(found, "0x7D in payload must be escaped (not followed by original next byte)")
    }

    // MARK: - Multiple frames in one buffer

    func testHdlcDecoderMultipleFrames() {
        let frame1 = Data([0x01, 0x02])
        let frame2 = Data([0x03, 0x04, 0x05])
        let combined = HDLC.frame(frame1) + HDLC.frame(frame2)
        let decoder = HDLC.FrameDecoder()
        let frames = decoder.feed(combined)
        XCTAssertEqual(frames.count, 2, "HDLC decoder must handle two concatenated frames")
        XCTAssertEqual(frames[0], frame1)
        XCTAssertEqual(frames[1], frame2)
    }

    // MARK: - Interface hash (mirrors TCPClientInterface)

    func testHashIsDeterministic() {
        let a = BackboneInterface(name: "same", host: "1.2.3.4", port: 1234)
        let b = BackboneInterface(name: "same", host: "1.2.3.4", port: 1234)
        XCTAssertEqual(a.hash, b.hash, "hash must be deterministic for the same name")
    }

    func testHashDependsOnName() {
        let a = BackboneInterface(name: "backbone-a", host: "1.2.3.4", port: 1234)
        let b = BackboneInterface(name: "backbone-b", host: "1.2.3.4", port: 1234)
        XCTAssertNotEqual(a.hash, b.hash, "different names must produce different hashes")
    }

    // MARK: - ReticulumConfig parsing

    func testSynthesizedFromConfig() throws {
        let ini = """
        [interfaces]
          [[backbone]]
          type = BackboneInterface
          enabled = yes
          name = MyBackbone
          target_host = 10.0.0.1
          target_port = 4242
        """
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BackboneConfigTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let cfgURL = tmpDir.appendingPathComponent("config")
        try ini.write(to: cfgURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        guard let cfg = ReticulumConfig.load(from: cfgURL) else {
            XCTFail("ReticulumConfig.load must succeed for valid config")
            return
        }

        // Verify the config parser recognises BackboneInterface
        XCTAssertFalse(cfg.interfaces.isEmpty, "config must parse at least one interface")
        let backbone = cfg.interfaces.first
        XCTAssertEqual(backbone?.type, "BackboneInterface",
                       "config parser must recognise 'BackboneInterface' type")
    }
}
