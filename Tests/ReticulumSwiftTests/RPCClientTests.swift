import XCTest
@testable import ReticulumSwift

/// Round-trip tests for ``RPCClient`` against the in-process ``RPCServer``.
///
/// Python reference: `RNS/Reticulum.py` — `get_rpc_client()` plus every accessor
/// guarded by `if self.is_connected_to_shared_instance:`.
///
/// These bind loopback sockets only, in the same way `LocalInterfaceTests` and
/// `BackboneInterfaceTests` already do.
final class RPCClientTests: XCTestCase {

    private var server: RPCServer?
    private var transport: Transport?
    private var port: UInt16 = 0
    private let authkey = Data((0..<32).map { UInt8($0) })

    override func tearDown() {
        server?.stop()
        server = nil
        transport = nil
        super.tearDown()
    }

    /// Bring up an `RPCServer` on a free loopback port and return a client bound to it.
    private func startServer(file: StaticString = #filePath, line: UInt = #line) throws -> RPCClient {
        let transport = Transport()
        self.transport = transport

        // Retry a few ports — the suite runs in parallel with other socket tests.
        var lastError: Error?
        for _ in 0..<20 {
            let candidate = UInt16.random(in: 41_000...48_000)
            let server = RPCServer(port: candidate, authkey: authkey)
            server.transport = transport
            do {
                try server.start()
                self.server = server
                self.port = candidate
                // Give NWListener a moment to reach .ready before the first connect.
                let deadline = Date().addingTimeInterval(2)
                while Date() < deadline {
                    if RPCClient.isSharedInstanceRunning(port: candidate, timeout: 0.2) { break }
                    usleep(20_000)
                }
                return RPCClient(host: "127.0.0.1", port: candidate, authkey: authkey, timeout: 3)
            } catch {
                lastError = error
            }
        }
        throw try XCTUnwrap(lastError, "could not bind any loopback port", file: file, line: line)
    }

    // MARK: - Handshake + call round trip

    func testInterfaceStats_roundTrip() throws {
        let client = try startServer()
        let stats = try client.interfaceStats()
        guard case .map(let pairs) = stats else {
            return XCTFail("interface_stats should decode as a map, got \(stats)")
        }
        let keys = pairs.compactMap { key, _ -> String? in
            if case .string(let s) = key { return s }
            return nil
        }
        // Python's get_interface_stats() always returns these top-level keys.
        XCTAssertTrue(keys.contains("interfaces"))
        XCTAssertTrue(keys.contains("rxb"))
        XCTAssertTrue(keys.contains("txb"))
        XCTAssertTrue(keys.contains("rxs"))
        XCTAssertTrue(keys.contains("txs"))
    }

    func testPathTable_emptyTransport_returnsEmptyArray() throws {
        let client = try startServer()
        guard case .array(let entries) = try client.pathTable() else {
            return XCTFail("path_table should decode as an array")
        }
        XCTAssertTrue(entries.isEmpty)
    }

    func testPathTable_withKnownPath_returnsEntry() throws {
        let client = try startServer()
        let transport = try XCTUnwrap(self.transport)
        let destination = randomHash()
        let via = randomHash()
        transport.restore(path: Transport.PathEntry(
            destinationHash: destination,
            nextHopInterfaceName: "TestIface",
            hops: 3,
            lastHeard: Date(),
            identityHash: randomHash(),
            nextHopTransportID: via
        ), forDestination: destination)

        guard case .array(let entries) = try client.pathTable(), let first = entries.first,
              case .map(let pairs) = first else {
            return XCTFail("expected one path table entry")
        }
        var fields: [String: MsgPack.Value] = [:]
        for (key, value) in pairs {
            if case .string(let name) = key { fields[name] = value }
        }
        XCTAssertEqual(fields["hash"], .bytes(destination))
        XCTAssertEqual(fields["via"], .bytes(via))
        XCTAssertEqual(fields["hops"]?.asInt, 3)
        XCTAssertEqual(fields["interface"], .string("TestIface"))
    }

    func testLinkCount_roundTrip() throws {
        let client = try startServer()
        XCTAssertEqual(try client.linkCount(), 0)
    }

    func testRateTable_roundTrip() throws {
        let client = try startServer()
        guard case .array = try client.rateTable() else {
            return XCTFail("rate_table should decode as an array")
        }
    }

    func testNextHop_unknownDestination_returnsNil() throws {
        let client = try startServer()
        XCTAssertNil(try client.nextHop(destinationHash: randomHash()))
    }

    func testBlackholeRoundTrip() throws {
        let client = try startServer()
        let identityHash = randomHash()
        XCTAssertFalse(try client.isBlackholed(identityHash: identityHash))
        try client.blackholeIdentity(identityHash, reason: "test")
        XCTAssertTrue(try client.isBlackholed(identityHash: identityHash))
        XCTAssertNotNil(try client.blackholedIdentities()[identityHash])
        try client.unblackholeIdentity(identityHash)
        XCTAssertFalse(try client.isBlackholed(identityHash: identityHash))
    }

    func testBlackholedIdentities_carriesFullEntry() throws {
        // Python's Transport.blackholed_identities maps each hash to
        // {"source", "until", "reason"}, and rnpath -b reads all three off it.
        // Returning a bare `true` per hash would break that rendering.
        let client = try startServer()
        let owner = Identity()
        try XCTUnwrap(transport).ownerIdentity = owner

        let identityHash = randomHash()
        let until = Date().timeIntervalSince1970 + 3600
        try client.blackholeIdentity(identityHash, until: until, reason: "spamming announces")

        let entry = try XCTUnwrap(try client.blackholedIdentities()[identityHash])
        XCTAssertEqual(entry.reason, "spamming announces")
        XCTAssertEqual(try XCTUnwrap(entry.until), until, accuracy: 0.001)
        // Python: entry["source"] = Transport.identity.hash — rnpath compares this against
        // its own identity to decide whether to print " by <hash>".
        XCTAssertEqual(entry.source, owner.hash)
    }

    func testBlackholedIdentities_nilFieldsSurviveRoundTrip() throws {
        let client = try startServer()
        let identityHash = randomHash()
        try client.blackholeIdentity(identityHash)

        let entry = try XCTUnwrap(try client.blackholedIdentities()[identityHash])
        XCTAssertNil(entry.until, "an indefinite blackhole carries a nil expiry")
        XCTAssertNil(entry.reason)
    }

    func testDropPath_removesPath() throws {
        let client = try startServer()
        let transport = try XCTUnwrap(self.transport)
        let destination = randomHash()
        transport.restore(path: Transport.PathEntry(
            destinationHash: destination,
            nextHopInterfaceName: "TestIface",
            hops: 1,
            lastHeard: Date(),
            identityHash: randomHash()
        ), forDestination: destination)

        try client.dropPath(destinationHash: destination)

        guard case .array(let entries) = try client.pathTable() else {
            return XCTFail("path_table should decode as an array")
        }
        XCTAssertTrue(entries.isEmpty, "dropped path should no longer be listed")
    }

    // MARK: - Authentication

    func testWrongAuthkey_isRejected() throws {
        _ = try startServer()
        let wrongClient = RPCClient(host: "127.0.0.1", port: port,
                                    authkey: Data(repeating: 0xEE, count: 32), timeout: 3)
        XCTAssertThrowsError(try wrongClient.interfaceStats())
    }

    func testConnectionRefused_whenNothingListening() {
        // Port 1 is privileged and never bound by this suite.
        let client = RPCClient(host: "127.0.0.1", port: 1, authkey: authkey, timeout: 1)
        XCTAssertThrowsError(try client.interfaceStats()) { error in
            guard case RPCClientError.connectionFailed = error else {
                return XCTFail("expected connectionFailed, got \(error)")
            }
        }
    }

    // MARK: - Auth key derivation

    func testAuthkeyDerivation_matchesInstanceDerivation() throws {
        // Python: rpc_key = Identity.full_hash(Transport.internal_identity().get_private_key())
        let storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("rpcclient-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storage) }

        let identity = Identity()
        try identity.write(toFile: storage.appendingPathComponent("transport_identity"))

        let derived = try RPCClient.authkey(storagePath: storage)
        let expected = Identity.fullHash(try XCTUnwrap(identity.getPrivateKey()))
        XCTAssertEqual(derived, expected)
    }

    func testAuthkeyDerivation_missingIdentity_throws() {
        let storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("rpcclient-missing-\(UUID().uuidString)")
        XCTAssertThrowsError(try RPCClient.authkey(storagePath: storage)) { error in
            guard case RPCClientError.noInstanceIdentity = error else {
                return XCTFail("expected noInstanceIdentity, got \(error)")
            }
        }
    }

    // MARK: - Shared-instance probe

    func testIsSharedInstanceRunning_falseWhenNothingListening() {
        XCTAssertFalse(RPCClient.isSharedInstanceRunning(port: 1, timeout: 0.5))
    }

    func testIsSharedInstanceRunning_trueWhenServerBound() throws {
        _ = try startServer()
        XCTAssertTrue(RPCClient.isSharedInstanceRunning(port: port, timeout: 1))
    }

    // MARK: - Defaults

    func testDefaultPorts() {
        // Python: Reticulum.local_control_port = 37429, shared_instance_port = 37428
        XCTAssertEqual(RPCClient.defaultControlPort, 37429)
        XCTAssertEqual(RPCClient.defaultSharedInstancePort, 37428)
    }

    // MARK: - Helpers

    private func randomHash() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    }
}
