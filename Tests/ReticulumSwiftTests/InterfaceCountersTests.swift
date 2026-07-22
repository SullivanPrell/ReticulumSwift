import XCTest
@testable import ReticulumSwift

/// Traffic counters (`rxBytes`/`txBytes`/`rxPackets`/`txPackets`) are written
/// from whichever queue an interface's I/O happens to run on — CoreBluetooth's
/// dispatch queue, a `NWConnection` queue, a serial-port read thread — while
/// being read from an entirely different one (the UI polls them for the
/// interface list, `rnstatus`-style output reads them for reporting).
///
/// `Int` is not atomic. `counter += 1` is a load-modify-store, so two queues
/// incrementing concurrently silently lose updates, and a concurrent reader can
/// observe a torn value. Both are undefined behaviour under the Swift memory
/// model, not merely inaccurate statistics.
///
/// A caveat on what these tests actually prove. The `InterfaceCounters` tests
/// below are ordinary assertions and would fail loudly on an unguarded counter.
/// The *interface-level* test is different: its assertions passed even against
/// the unguarded implementation, because a few thousand iterations with real
/// work between increments rarely interleave at exactly the wrong instruction.
/// Lost updates are probabilistic; the race is not.
///
/// So the interface test earns its keep under the Thread Sanitizer, which flags
/// the unsynchronized access whether or not an update was actually lost:
///
///     swift test --sanitize=thread --filter InterfaceCountersTests
///
/// Run that way it reported the race before the fix and is silent after. Do not
/// mistake a green plain `swift test` here for proof of thread safety.
final class InterfaceCountersTests: XCTestCase {

    // MARK: - The counter type itself

    func testConcurrentIncrementsLoseNoUpdates() {
        let counters = InterfaceCounters()
        let threads = 8
        let perThread = 5_000

        DispatchQueue.concurrentPerform(iterations: threads) { _ in
            for _ in 0..<perThread {
                counters.addTx(bytes: 10)
                counters.addRx(bytes: 3)
            }
        }

        let total = threads * perThread
        XCTAssertEqual(counters.txPackets, total)
        XCTAssertEqual(counters.rxPackets, total)
        XCTAssertEqual(counters.txBytes, total * 10)
        XCTAssertEqual(counters.rxBytes, total * 3)
    }

    /// A reader must never observe a half-applied update — `snapshot()` takes
    /// all four counters under one lock acquisition, so bytes and packets are
    /// always consistent with each other.
    func testSnapshotIsInternallyConsistent() {
        let counters = InterfaceCounters()
        let done = expectation(description: "writer finished")

        DispatchQueue.global().async {
            for _ in 0..<20_000 { counters.addTx(bytes: 100) }
            done.fulfill()
        }

        // Every observed snapshot must satisfy the invariant the writer
        // maintains: exactly 100 bytes per packet.
        for _ in 0..<5_000 {
            let s = counters.snapshot()
            XCTAssertEqual(s.txBytes, s.txPackets * 100)
        }

        wait(for: [done], timeout: 10)
        XCTAssertEqual(counters.txPackets, 20_000)
    }

    func testResetClearsEveryCounter() {
        let counters = InterfaceCounters()
        counters.addTx(bytes: 40)
        counters.addRx(bytes: 60)
        counters.reset()

        let s = counters.snapshot()
        XCTAssertEqual(s.txBytes, 0)
        XCTAssertEqual(s.rxBytes, 0)
        XCTAssertEqual(s.txPackets, 0)
        XCTAssertEqual(s.rxPackets, 0)
    }

    // MARK: - A real interface under its real access pattern

    /// `BLEMeshInterface` is the sharpest case in the library: `send` runs on
    /// whichever thread `Transport` dispatches from, `handlePeerData` runs on
    /// CoreBluetooth's queue, and the app polls the counters from the main
    /// thread on a timer. All three touch the same four `Int`s.
    func testInterfaceCountersSurviveConcurrentSendAndReceive() throws {
        let transport = ThreadSafeMockBLETransport()
        let iface = BLEMeshInterface(name: "race", transport: transport)
        try iface.start()

        let peer: BLEMeshPeerID = "peer-1"
        transport.simulateConnect(peer)

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xCD, count: Constants.truncatedHashLength),
            data: Data("race".utf8)
        )
        // Pre-frame one packet so the receive side feeds well-formed frames.
        let framed = HDLC.frame(try packet.pack())

        let rounds = 2_000
        let sendDone = expectation(description: "sends finished")
        let recvDone = expectation(description: "receives finished")

        DispatchQueue.global().async {
            for _ in 0..<rounds { try? iface.send(packet) }
            sendDone.fulfill()
        }
        DispatchQueue.global().async {
            for _ in 0..<rounds { transport.simulateReceive(from: peer, chunk: framed) }
            recvDone.fulfill()
        }
        // A third participant reading concurrently, as the UI does.
        DispatchQueue.global().async {
            for _ in 0..<rounds { _ = iface.txBytes + iface.rxBytes }
        }

        wait(for: [sendDone, recvDone], timeout: 30)

        XCTAssertEqual(iface.txPackets, rounds, "outbound packet count lost updates")
        XCTAssertEqual(iface.rxPackets, rounds, "inbound packet count lost updates")
    }
}

// MARK: - Mock transport

/// Minimal `BLEMeshTransport` whose `send` is safe to call from several queues
/// at once — the interface, not the mock, is what is under test here.
private final class ThreadSafeMockBLETransport: BLEMeshTransport, @unchecked Sendable {
    var peerConnected: ((BLEMeshPeerID) -> Void)?
    var peerDisconnected: ((BLEMeshPeerID) -> Void)?
    var peerDataHandler: ((BLEMeshPeerID, Data) -> Void)?

    private let lock = NSLock()
    private var sentCount = 0
    private var peers: [BLEMeshPeerID] = []

    var connectedPeers: [BLEMeshPeerID] {
        lock.lock(); defer { lock.unlock() }
        return peers
    }

    func start() throws {}
    func stop() {}

    func send(_ data: Data, to peer: BLEMeshPeerID) throws {
        lock.lock(); sentCount += 1; lock.unlock()
    }

    func simulateConnect(_ peer: BLEMeshPeerID) {
        lock.lock(); peers.append(peer); lock.unlock()
        peerConnected?(peer)
    }
    func simulateReceive(from peer: BLEMeshPeerID, chunk: Data) {
        peerDataHandler?(peer, chunk)
    }
}
