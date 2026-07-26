import XCTest
@testable import ReticulumSwift

/// Regression coverage for the shared-instance client's *startup* traffic.
///
/// Bug: `LocalInterface.start()` returned as soon as `NWConnection.start()` had
/// been called, long before the connection reached `.ready`. Since `send()`
/// silently discards packets while `isOnline == false`, everything a local
/// client emitted in that window went nowhere — most visibly the announce that
/// every utility fires immediately after attaching (`rncp -l`, `rnid -a`, the
/// LXMF delivery announce in RetiOS). The daemon accepted the socket and
/// reported "Serving: 1 program", but its path table stayed empty, so a Swift
/// local client behind a Swift shared instance was unreachable from the mesh.
/// A *Python* client on the same Swift daemon worked, which is what made the
/// fault look like a daemon-side forwarding gap rather than a client-side one.
///
/// Python has no such window: `LocalClientInterface.connect()`
/// (RNS/Interfaces/LocalInterface.py:140) calls a blocking `socket.connect()`
/// and only then sets `self.online = True`, so by the time
/// `Reticulum.__start_local_client` returns the interface can already send —
/// and if it cannot connect at all it raises rather than coming up dead.
final class LocalInterfaceReadinessTests: XCTestCase {

    private var servers: [PosixTCPServer] = []
    private var clients: [LocalInterface] = []

    override func tearDown() {
        for client in clients { client.stop() }
        for server in servers { server.stop() }
        clients = []
        servers = []
        super.tearDown()
    }

    private func freePort() -> UInt16 { UInt16.random(in: 41_000...48_000) }

    /// Stand up a shared-instance server on a throwaway port, retrying a couple
    /// of times in case the random port is already taken by something else.
    private func startServer() throws -> PosixTCPServer {
        for _ in 0..<8 {
            let server = PosixTCPServer(name: "Shared Instance", port: freePort())
            do {
                try server.start()
                servers.append(server)
                return server
            } catch {
                continue
            }
        }
        throw XCTSkip("no free port available for the shared-instance server")
    }

    private func makeClient(port: UInt16) -> LocalInterface {
        let client = LocalInterface(host: "127.0.0.1", port: port)
        clients.append(client)
        return client
    }

    // MARK: - The interface itself

    /// The core contract: once `start()` returns, `send()` must actually put
    /// bytes on the wire. No sleep, no polling for `isOnline` — exactly what a
    /// utility does when it announces on the line after attaching.
    func testStartBlocksUntilTheInterfaceCanSend() throws {
        let server = try startServer()
        let received = expectation(description: "server received the frame")
        server.rawInboundHandler = { _, _ in received.fulfill() }

        let client = makeClient(port: server.port)
        try client.start()

        XCTAssertTrue(client.isOnline, "start() must not return before the connection is usable")

        let packet = Packet(destinationType: .plain,
                            packetType: .data,
                            destinationHash: Data(repeating: 0xAB, count: 16),
                            data: Data("startup".utf8))
        try client.send(packet)

        wait(for: [received], timeout: 5)
    }

    /// Python raises out of `connect()` when the shared instance is not there;
    /// `InstanceConnection.attach` already documents that outcome as
    /// `couldNotConnect`, which was unreachable while `start()` could not fail.
    func testStartThrowsWhenNothingIsListening() throws {
        let client = makeClient(port: freePort())
        client.connectTimeout = 1
        XCTAssertThrowsError(try client.start()) { error in
            guard case LocalInterface.ConnectionError.couldNotConnect = error else {
                return XCTFail("expected couldNotConnect, got \(error)")
            }
        }
        XCTAssertFalse(client.isOnline)
    }

    /// A failed initial connect must not leave a reconnect timer running: Python
    /// raises out of the constructor and the interface is discarded.
    func testFailedStartLeavesNothingRunning() throws {
        let client = makeClient(port: freePort())
        client.connectTimeout = 1
        client.reconnectWait = 0.1
        XCTAssertThrowsError(try client.start())

        let settled = expectation(description: "no reconnect brings it online")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.75) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertFalse(client.isOnline, "a failed start must not keep retrying behind the caller's back")
    }

    // MARK: - End to end, through Transport

    /// The reported symptom, reproduced at the library level: a client attaches
    /// to a shared instance and announces straight away; the daemon must learn
    /// a path to that destination.
    func testStartupAnnounceReachesTheSharedInstancePathTable() throws {
        let server = try startServer()

        // Daemon side — a non-transport shared instance, as most rnsd installs are.
        let daemon = Transport()
        daemon.transportEnabled = false
        daemon.register(interface: server)
        defer { daemon.stop() }

        // Client side — exactly what InstanceConnection.attach does for a local client.
        let client = Transport()
        client.transportEnabled = false
        client.isConnectedToSharedInstance = true
        let localInterface = makeClient(port: server.port)
        client.register(interface: localInterface)
        try localInterface.start()
        defer { client.stop() }

        let identity = Identity()
        let destination = try Destination(identity: identity, direction: .in, kind: .single, appName: "rncp")
        client.register(destination: destination)

        // No sleep between attaching and announcing — this is the window the bug lived in.
        _ = try client.announce(destination: destination, appData: Data("startup".utf8))

        let learned = expectation(description: "daemon learned a path")
        let poll = DispatchQueue(label: "path-poll")
        func check(_ remaining: Int) {
            if daemon.hasPath(to: destination.hash) { return learned.fulfill() }
            guard remaining > 0 else { return }
            poll.asyncAfter(deadline: .now() + 0.05) { check(remaining - 1) }
        }
        poll.async { check(100) }
        wait(for: [learned], timeout: 8)

        XCTAssertEqual(daemon.hopsTo(destination.hash), 0, "a directly attached local client is zero hops away")
        XCTAssertEqual(daemon.nextHopInterfaceName(for: destination.hash), server.name)
    }
}
