import XCTest
@testable import ReticulumSwift

/// `announce_cap` is a **per-interface** fraction of capacity announces may consume: Python
/// writes it from config (`Reticulum.py:912`, defaulting to `ANNOUNCE_CAP/100`) and consumes it
/// per interface as `wait_time = tx_time / interface.announce_cap` (`Transport.py:1284`,
/// `:2893`).
///
/// The port parsed it, validated it, wrote it onto the interface and let spawned clients
/// inherit it — and then every rate computation read the hardcoded static
/// `AnnounceQueue.announceCap` (2%). `bugs/025` with the roles swapped: a value that is never
/// read fails exactly as one that is never written. An operator raising the cap on a fast
/// backbone, or lowering it on a slow LoRa link, changed nothing.
final class AnnounceCapConsumerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AnnounceQueue.jitterMultiplierOverride = 0   // deterministic windows
    }

    override func tearDown() {
        AnnounceQueue.jitterMultiplierOverride = nil
        super.tearDown()
    }

    private func announcePacket() -> Packet {
        Packet(destinationType: .single, packetType: .announce,
               destinationHash: Data(repeating: 0x11, count: 16),
               context: .none, data: Data(repeating: 0xCD, count: 100))
    }

    /// The rate window is `txTime / cap`, so a larger cap must admit the next announce sooner.
    /// Each probe gets a fresh queue: once an announce is queued the fast path is skipped
    /// entirely, so a single queue could only ever show the first window.
    func testTheRateWindowFollowsThePerInterfaceCap() {
        let packet = announcePacket()
        let bitrate = 10_000
        let txTime = Double(packet.rawByteCount) * 8.0 / Double(bitrate)

        func admits(at time: TimeInterval, cap: Double) -> Bool {
            let queue = AnnounceQueue()
            XCTAssertTrue(queue.shouldTransmit(packet: packet, now: 0, bitrate: bitrate,
                                               announceCap: cap, emitted: 0),
                          "the first announce always goes out")
            return queue.shouldTransmit(packet: packet, now: time,
                                        bitrate: bitrate, announceCap: cap, emitted: 0)
        }

        for cap in [0.02, 0.04, 0.5] {
            let window = txTime / cap
            XCTAssertFalse(admits(at: window * 0.9, cap: cap),
                           "cap \(cap): admitted inside its own rate window")
            XCTAssertTrue(admits(at: window * 1.1, cap: cap),
                          """
                          the queue admitted on the wrong schedule for cap \(cap) — it is \
                          computing tx_time / 0.02 regardless of what the interface says, so a \
                          configured announce_cap is parsed, written, inherited and ignored \
                          (Transport.py:1284)
                          """)
        }

        // And the caps are genuinely distinguishable: what a 50% cap admits, 2% does not.
        let fastWindow = txTime / 0.5 * 1.1
        XCTAssertTrue(admits(at: fastWindow, cap: 0.5))
        XCTAssertFalse(admits(at: fastWindow, cap: 0.02),
                       "a 25×-tighter cap must still be rate-limiting at that instant — if "
                       + "both answer the same, the cap argument is not being used")
    }

    /// The drain path computes the same window and had the same hardcoded divisor.
    func testDrainHonoursThePerInterfaceCap() {
        let packet = announcePacket()
        let bitrate = 10_000
        let txTime = Double(packet.rawByteCount) * 8.0 / Double(bitrate)
        let cap = 0.5
        let queue = AnnounceQueue()

        _ = queue.shouldTransmit(packet: packet, now: 0, bitrate: bitrate,
                                 announceCap: cap, emitted: 0)
        _ = queue.shouldTransmit(packet: packet, now: 0, bitrate: bitrate,
                                 announceCap: cap, emitted: 1)
        XCTAssertEqual(queue.count, 1, "the second announce is queued behind the window")

        let early = queue.drain(now: txTime / cap * 0.5, bitrate: bitrate, announceCap: cap)
        XCTAssertTrue(early.isEmpty, "still inside the window")
        let due = queue.drain(now: txTime / cap * 1.5, bitrate: bitrate, announceCap: cap)
        XCTAssertEqual(due.count, 1,
                       "the drain path must use the interface's cap too — it had the same "
                       + "hardcoded 2% divisor as the admission path")
    }

    /// The interface default is Python's `ANNOUNCE_CAP/100`, so an unconfigured interface
    /// behaves exactly as before this fix.
    func testAnUnconfiguredInterfaceKeepsTheReferenceDefault() {
        let iface = TCPClientInterface(name: "Uplink", host: "127.0.0.1", port: 4965)
        XCTAssertEqual(iface.announceCap, Double(Reticulum.announceCap) / 100.0, accuracy: 1e-9)
    }

    /// End to end through the production path: the value an operator writes in the config is
    /// the value the queue divides by.
    func testAConfiguredCapReachesTheQueue() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rns_cap_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stack = Reticulum(configuration: .init(storagePath: tempDir, shareInstance: false))
        try stack.synthesizeInterfaces(from: ReticulumConfig.parse("""
        [reticulum]
          enable_transport = no
          share_instance = no

        [interfaces]
          [[Fast Link]]
            type = TCPClientInterface
            enabled = yes
            target_host = 127.0.0.1
            target_port = 4965
            announce_cap = 25
        """))
        let iface = try XCTUnwrap(stack.transport.interfaces.first { $0.name == "Fast Link" })
        XCTAssertEqual(iface.announceCap, 0.25, accuracy: 1e-9,
                       "config carries a percentage; the interface holds the fraction "
                       + "(Reticulum.py:834-837)")
    }
}
