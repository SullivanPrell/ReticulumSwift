import XCTest
import Network
@testable import ReticulumSwift

/// `TCPClientInterface` must redial after the peer goes away.
///
/// Python has done this since forever: `RECONNECT_WAIT = 5`,
/// `RECONNECT_MAX_TRIES = None`, and a `reconnect()` thread that retries until it is back
/// (`TCPInterface.py:80-81`, `:270-293`). ReticulumSwift dialed once from `start()` and,
/// on peer FIN, `beginReceiveLoop` merely set `isOnline = false` and returned — no log, no
/// `cancel()`, no redial.
///
/// Found via bug 013. A public transit node that accepts and immediately hangs up (normal
/// churn on the community backbones) took a Swift node permanently offline with nothing in
/// the log, while the dead connection sat in `CLOSE_WAIT` for the life of the process. The
/// same condition is a five-second blip for a Python node. Every other reconnecting
/// interface in the port — `LocalInterface`, `BackboneInterface`, `I2PInterfacePeer`, both
/// RNode interfaces — already had this; the TCP client was the only one that did not.
final class TCPClientInterfaceReconnectTests: XCTestCase {

    /// A listener that counts accepted connections, and can be told to hang up on each one
    /// the moment it arrives — the behaviour that exposed the bug.
    private final class CountingListener {
        let port: UInt16
        private let listener: NWListener
        private let lock = NSLock()
        private var accepted = 0
        private var live: [NWConnection] = []
        private let hangUp: Bool

        var acceptCount: Int { lock.lock(); defer { lock.unlock() }; return accepted }

        init(hangUp: Bool) throws {
            self.hangUp = hangUp
            var made: (NWListener, UInt16)?
            for _ in 0..<16 {
                let candidate = UInt16.random(in: 41_000...48_000)
                guard let nwPort = NWEndpoint.Port(rawValue: candidate) else { continue }
                if let l = try? NWListener(using: .tcp, on: nwPort) { made = (l, candidate); break }
            }
            guard let made else { throw XCTSkip("no free port for the test listener") }
            self.listener = made.0
            self.port = made.1

            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                self.lock.lock()
                self.accepted += 1
                if !self.hangUp { self.live.append(conn) }
                self.lock.unlock()
                conn.start(queue: .global())
                if self.hangUp { conn.cancel() }
            }
            listener.start(queue: .global())
        }

        /// Drop every connection currently held open.
        func dropAll() {
            lock.lock(); let all = live; live = []; lock.unlock()
            for c in all { c.cancel() }
        }

        func stop() {
            dropAll()
            listener.cancel()
        }
    }

    private var listeners: [CountingListener] = []
    private var interfaces: [TCPClientInterface] = []

    override func tearDown() {
        for i in interfaces { i.stop() }
        for l in listeners { l.stop() }
        interfaces = []
        listeners = []
        super.tearDown()
    }

    private func makeListener(hangUp: Bool) throws -> CountingListener {
        let l = try CountingListener(hangUp: hangUp)
        listeners.append(l)
        return l
    }

    private func makeClient(port: UInt16, reconnectWait: TimeInterval = 0.3) -> TCPClientInterface {
        let iface = TCPClientInterface(name: "remote", host: "127.0.0.1", port: port)
        iface.reconnectWait = reconnectWait
        interfaces.append(iface)
        return iface
    }

    /// Spin until `predicate` holds, or fail after `timeout` of *scheduled* time.
    ///
    /// The budget is spent by polling, not by the wall clock. Under enough system load
    /// this process gets descheduled for minutes at a stretch — a run of these tests whose
    /// body is a bare `Thread.sleep(1.5)` has been observed taking 954 seconds — during
    /// which the network callbacks being waited on are frozen too. A wall-clock deadline
    /// turns that into a spurious failure; charging only the time a poll interval was
    /// meant to take keeps the timeout tight when the machine is healthy and rides out a
    /// stall when it is not.
    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 10,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ predicate: () -> Bool) {
        let interval: TimeInterval = 0.05
        var spent: TimeInterval = 0
        while spent < timeout {
            if predicate() { return }
            let before = Date()
            Thread.sleep(forTimeInterval: interval)
            // Charge the interval we asked for, not the (possibly enormous) one we got.
            spent += min(Date().timeIntervalSince(before), interval * 4)
        }
        XCTFail("timed out waiting for \(description)", file: file, line: line)
    }

    // MARK: - Defaults

    /// Python: `RECONNECT_WAIT = 5`, `RECONNECT_MAX_TRIES = None`.
    func testDefaultsMatchPython() {
        let iface = TCPClientInterface(name: "remote", host: "127.0.0.1", port: 4242)
        XCTAssertEqual(iface.reconnectWait, 5)
        XCTAssertNil(iface.maxReconnectTries, "unlimited reconnects by default")
    }

    // MARK: - The regression

    /// The exact bug-013 condition: the peer accepts and immediately sends FIN.
    /// Python redials every `RECONNECT_WAIT`; Swift used to stop forever after the first.
    func testRedialsAfterThePeerHangsUpImmediately() throws {
        let listener = try makeListener(hangUp: true)
        let iface = makeClient(port: listener.port)
        try iface.start()

        waitUntil("a third dial") { listener.acceptCount >= 3 }
    }

    /// A connection that comes up cleanly and is dropped later must also be redialed.
    func testRedialsAfterAnEstablishedConnectionDrops() throws {
        let listener = try makeListener(hangUp: false)
        let iface = makeClient(port: listener.port)
        try iface.start()
        waitUntil("the interface to come up", timeout: 5) { iface.isOnline }

        let acceptsBeforeDrop = listener.acceptCount
        listener.dropAll()

        waitUntil("a redial") { listener.acceptCount > acceptsBeforeDrop }
    }

    /// The dead connection has to be cancelled, or it sits in CLOSE_WAIT for the life of
    /// the process — one leaked socket per drop.
    func testTheSupersededConnectionIsCancelled() throws {
        let listener = try makeListener(hangUp: false)
        let iface = makeClient(port: listener.port)
        try iface.start()
        waitUntil("the interface to come up", timeout: 5) { iface.isOnline }

        let firstConnection = try XCTUnwrap(iface.currentConnectionForTesting)
        let acceptsBeforeDrop = listener.acceptCount
        listener.dropAll()
        waitUntil("a redial") { listener.acceptCount > acceptsBeforeDrop }

        waitUntil("the dropped connection to be cancelled") {
            if case .cancelled = firstConnection.state { return true }
            return false
        }
    }

    /// `stop()` must end the retry loop; a stopped interface that keeps dialing is a socket
    /// leak and, for a utility that tears its stack down, a hang.
    func testStopEndsTheRetryLoop() throws {
        let listener = try makeListener(hangUp: true)
        let iface = makeClient(port: listener.port)
        try iface.start()
        waitUntil("a redial") { listener.acceptCount >= 2 }

        iface.stop()
        Thread.sleep(forTimeInterval: 0.5)      // let anything already in flight land
        let settled = listener.acceptCount
        Thread.sleep(forTimeInterval: 1.5)      // several reconnectWait periods
        XCTAssertEqual(listener.acceptCount, settled,
                       "a stopped interface must not keep dialing")
    }

    /// A port nobody is listening on, for the "never connects" cases.
    private func deadPort() throws -> UInt16 {
        let listener = try makeListener(hangUp: true)
        let port = listener.port
        listener.stop()
        listeners.removeAll { $0 === listener }
        return port
    }

    /// Python stops retrying once `max_reconnect_tries` is exceeded
    /// (`TCPInterface.py:277-281`).
    ///
    /// The cap counts *consecutive* failures: `attempts` is local to one `reconnect()`
    /// call and the loop exits as soon as `self.online`, so a peer that keeps accepting
    /// and hanging up is retried forever in Python too. Only a peer that never completes
    /// a connection exhausts the budget — which is what this uses.
    func testMaxReconnectTriesIsHonoured() throws {
        let port = try deadPort()
        let iface = makeClient(port: port)
        iface.maxReconnectTries = 2
        try iface.start()

        Thread.sleep(forTimeInterval: 3)        // ~10 reconnectWait periods
        XCTAssertLessThanOrEqual(iface.dialCountForTesting, 3,
                                 "initial dial plus at most maxReconnectTries redials")
    }

    /// An interface pointed at a port nobody is listening on keeps trying, rather than
    /// coming up dead and silent. Python: `initial_connect()` failing starts `reconnect()`,
    /// which retries forever by default.
    func testAnUnreachablePeerKeepsBeingRetried() throws {
        let iface = makeClient(port: try deadPort())
        try iface.start()
        waitUntil("a retry after the refused connection") { iface.dialCountForTesting >= 2 }
        XCTAssertFalse(iface.isOnline)
    }
}
