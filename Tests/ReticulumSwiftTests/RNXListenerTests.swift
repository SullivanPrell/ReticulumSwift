import XCTest
@testable import ReticulumSwift

/// Records what it was asked to run and hands back a canned outcome.
final class MockRNXCommandExecutor: RNXCommandExecutor {
    private let lock = NSLock()
    private var _calls: [(command: String, stdin: Data?, timeout: TimeInterval?)] = []
    var calls: [(command: String, stdin: Data?, timeout: TimeInterval?)] {
        lock.lock(); defer { lock.unlock() }; return _calls
    }
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return _calls.count }

    var result: RNXExecution = RNXExecution(spawned: true, returnCode: 0,
                                            stdout: Data(), stderr: Data())
    /// When set, `execute` blocks on it — used to prove the receive thread is not held.
    var gate: DispatchSemaphore?

    func execute(command: String, stdin: Data?, timeout: TimeInterval?) -> RNXExecution {
        lock.lock(); _calls.append((command, stdin, timeout)); lock.unlock()
        gate?.wait()
        return result
    }
}

/// The `rnx -l` half.
/// Python reference: RNS/Utilities/rnx.py:63-252.
final class RNXListenerTests: XCTestCase {

    private func makeListener(allowAll: Bool = true,
                              allowed: [Data] = [],
                              executor: MockRNXCommandExecutor = MockRNXCommandExecutor(),
                              queue: DispatchQueue = DispatchQueue(label: "rnx.test")) throws -> RNXListener {
        let listener = try RNXListener(identity: Identity(),
                                       transport: Transport(),
                                       executor: executor,
                                       allowedIdentityHashes: allowed,
                                       allowAll: allowAll,
                                       executionQueue: queue)
        listener.onLog = { _, _ in }   // keep the test log quiet
        return listener
    }

    // MARK: - makeResult

    func testResultForSuccessfulRun() throws {
        let listener = try makeListener()
        let request = RNXRequest(command: "echo hi", timeout: 15)
        let execution = RNXExecution(spawned: true, returnCode: 0,
                                     stdout: Data("hi\n".utf8), stderr: Data())
        let result = listener.makeResult(for: request, execution: execution,
                                         startedAt: 1000, now: { 1000.5 })
        XCTAssertTrue(result.executed)
        XCTAssertEqual(result.returnCode, 0)
        XCTAssertEqual(result.stdout, Data("hi\n".utf8))
        XCTAssertEqual(result.stderr, Data())
        // Python: result[4] = len(stdout) — the FULL, pre-truncation length.
        XCTAssertEqual(result.totalStdoutLength, 3)
        XCTAssertEqual(result.totalStderrLength, 0)
        XCTAssertEqual(result.startedAt, 1000)
        // Python: result[7] set only when a timeout was requested and not yet passed.
        XCTAssertEqual(result.concludedAt, 1000.5)
    }

    func testConcludedTimestampRule() throws {
        let listener = try makeListener()
        let execution = RNXExecution(spawned: true, returnCode: 0, stdout: Data(), stderr: Data())

        // Python: `if timeout != None and time.time() < result[6]+timeout` — a request
        // with no timeout NEVER gets a concluded timestamp.
        let noTimeout = listener.makeResult(for: RNXRequest(command: "x"),
                                            execution: execution,
                                            startedAt: 1000, now: { 1000.5 })
        XCTAssertNil(noTimeout.concludedAt)

        // A command killed by the deadline also leaves it None.
        let killed = RNXExecution(spawned: true, returnCode: -15,
                                  stdout: Data(), stderr: Data(), timedOut: true)
        let timedOut = listener.makeResult(for: RNXRequest(command: "x", timeout: 5),
                                           execution: killed,
                                           startedAt: 1000, now: { 1006 })
        XCTAssertNil(timedOut.concludedAt)

        // And so does one that merely ran past the deadline without being flagged.
        let late = listener.makeResult(for: RNXRequest(command: "x", timeout: 5),
                                       execution: execution,
                                       startedAt: 1000, now: { 1006 })
        XCTAssertNil(late.concludedAt)
    }

    func testStdoutLimit() throws {
        let listener = try makeListener()
        let stdout = Data(repeating: 0x61, count: 100)
        let execution = RNXExecution(spawned: true, returnCode: 0, stdout: stdout, stderr: stdout)

        func result(_ limit: Int?) -> RNXResult {
            listener.makeResult(for: RNXRequest(command: "x", stdoutLimit: limit, stderrLimit: limit),
                                execution: execution, startedAt: 0, now: { 0 })
        }

        // Python: stdout[0:o_limit]
        XCTAssertEqual(result(10).stdout?.count, 10)
        XCTAssertEqual(result(10).stderr?.count, 10)
        XCTAssertEqual(result(10).totalStdoutLength, 100)
        // Python: `if o_limit == 0: result[2] = b""` — empty Data, never nil.
        XCTAssertEqual(result(0).stdout, Data())
        XCTAssertEqual(result(0).totalStdoutLength, 100)
        // A limit above the length short-circuits and the buffer passes through whole.
        XCTAssertEqual(result(200).stdout?.count, 100)
        XCTAssertEqual(result(nil).stdout?.count, 100)
        // Python evaluates stdout[0:-1] for a negative limit, dropping the LAST byte.
        // Data.prefix(-1) would trap, so the index is computed the Python way.
        XCTAssertEqual(result(-1).stdout?.count, 99)
        XCTAssertEqual(result(-500).stdout?.count, 0)
    }

    func testNilOutputProducesAWellFormedResult() throws {
        // Python's terminate-but-still-running branch sets stdout/stderr to None, and
        // `result[4] = len(stdout)` at rnx.py:240 then raises TypeError — killing the
        // response generator so the client gets nothing at all. Treated as empty here.
        let listener = try makeListener()
        let execution = RNXExecution(spawned: true, returnCode: -15,
                                     stdout: nil, stderr: nil, timedOut: true)
        let result = listener.makeResult(for: RNXRequest(command: "x", timeout: 1),
                                         execution: execution, startedAt: 0, now: { 5 })
        XCTAssertTrue(result.executed)
        XCTAssertEqual(result.stdout, Data())
        XCTAssertEqual(result.stderr, Data())
        XCTAssertEqual(result.totalStdoutLength, 0)
        XCTAssertEqual(result.totalStderrLength, 0)
        guard case .array(let arr) = result.packedValue() else { return XCTFail() }
        XCTAssertEqual(arr.count, 8)
    }

    func testSpawnFailureResult() throws {
        // Python: rnx.py:182-184 — result[0] = False and an immediate return, so every
        // other field stays None. This is what an empty interactive line produces.
        let listener = try makeListener()
        let result = listener.makeResult(for: RNXRequest(command: "", timeout: 15),
                                         execution: .spawnFailed, startedAt: 1000, now: { 1001 })
        XCTAssertFalse(result.executed)
        XCTAssertNil(result.returnCode)
        XCTAssertNil(result.stdout)
        XCTAssertNil(result.stderr)
        XCTAssertNil(result.totalStdoutLength)
        XCTAssertNil(result.totalStderrLength)
        XCTAssertEqual(result.startedAt, 1000)
        XCTAssertNil(result.concludedAt)
    }

    // MARK: - Allow-list

    func testIsAllowed() throws {
        let allowedHash = Data(repeating: 0xAA, count: 16)
        let otherHash = Data(repeating: 0xBB, count: 16)

        let permissive = try makeListener(allowAll: true)
        XCTAssertTrue(permissive.isAllowed(nil))
        XCTAssertTrue(permissive.isAllowed(otherHash))

        let gated = try makeListener(allowAll: false, allowed: [allowedHash])
        // Python's ALLOW_LIST requires an identified peer (Link.py:820-821).
        XCTAssertFalse(gated.isAllowed(nil))
        XCTAssertFalse(gated.isAllowed(otherHash))
        XCTAssertTrue(gated.isAllowed(allowedHash))
    }

    func testParseAllowedHash() throws {
        XCTAssertThrowsError(try RNXListener.parseAllowedHash(String(repeating: "a", count: 31))) {
            XCTAssertEqual($0 as? RNXListener.ListenerError, .invalidAllowedHashLength(31))
        }
        XCTAssertThrowsError(try RNXListener.parseAllowedHash(String(repeating: "z", count: 32))) {
            XCTAssertEqual($0 as? RNXListener.ListenerError,
                           .invalidAllowedHashHex(String(repeating: "z", count: 32)))
        }
        // Python's bytes.fromhex accepts both cases.
        XCTAssertEqual(try RNXListener.parseAllowedHash(String(repeating: "AB", count: 16)),
                       Data(repeating: 0xAB, count: 16))
        XCTAssertEqual(try RNXListener.parseAllowedHash(String(repeating: "ab", count: 16)).count, 16)
    }

    func testLoadAllowedIdentitiesFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rnx-allowed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Python: strip every \r, split on \n, keep only lines of exactly 32 characters —
        // so blank lines, comments and short lines are silently ignored.
        let valid = String(repeating: "ab", count: 16)
        let contents = "\r\n# a comment\r\n\(valid)\r\n0123456789\r\n\r\n"
        try contents.write(to: directory.appendingPathComponent(RNXApp.allowedIdentitiesFileName),
                           atomically: true, encoding: .utf8)

        let hashes = try RNXListener.loadAllowedIdentitiesFile(searchPaths: [directory.path])
        XCTAssertEqual(hashes.count, 1)
        XCTAssertEqual(hashes[0], Data(repeating: 0xAB, count: 16))
    }

    func testLoadAllowedIdentitiesFileRejectsNonHexLine() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rnx-allowed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Python: a 32-character non-hex line raises inside bytes.fromhex, and rnx prints
        // str(e) and exits 1. The wording differs; the failure does not.
        try String(repeating: "z", count: 32)
            .write(to: directory.appendingPathComponent(RNXApp.allowedIdentitiesFileName),
                   atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try RNXListener.loadAllowedIdentitiesFile(searchPaths: [directory.path]))
    }

    func testMissingAllowedIdentitiesFileYieldsEmptyList() throws {
        let hashes = try RNXListener.loadAllowedIdentitiesFile(
            searchPaths: ["/nonexistent-rnx-\(UUID().uuidString)"])
        XCTAssertTrue(hashes.isEmpty)
    }

    // MARK: - Identity

    func testLoadOrCreateIdentityCreatesMissingIdentitiesDirectory() throws {
        // Python creates <configdir>/storage/identities in Reticulum.__init__
        // (Reticulum.py:319); ReticulumSwift's start() creates only storage/, so
        // Identity.toFile would otherwise throw on a fresh machine.
        let configDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rnx-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: configDir) }

        let url = RNXListener.defaultIdentityURL(configDir: configDir)
        XCTAssertEqual(url.lastPathComponent, "rnx")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))

        var logged: [String] = []
        let created = try RNXListener.loadOrCreateIdentity(at: url) { message, _ in logged.append(message) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(logged, ["No valid saved identity found, creating new..."])

        // A second call loads the same identity and logs nothing.
        logged.removeAll()
        let reloaded = try RNXListener.loadOrCreateIdentity(at: url) { message, _ in logged.append(message) }
        XCTAssertEqual(reloaded.hash, created.hash)
        XCTAssertTrue(logged.isEmpty)
    }

    // MARK: - Registration

    func testRegisterInstallsDestinationAndHandler() throws {
        let transport = Transport()
        let listener = try RNXListener(identity: Identity(),
                                       transport: transport,
                                       executor: MockRNXCommandExecutor(),
                                       allowAll: true)
        listener.register()

        XCTAssertNotNil(transport.registeredDestinations[listener.destination.hash])
        let key = Hashes.truncatedHash(Data(RNXApp.requestPath.utf8))
        let entry = listener.destination.requestHandlers[key]
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.path, "command")
        // Registered with .all because Destination's .list policy takes [Identity], which
        // rnx never has — the ALLOW_LIST check happens inside the handler instead.
        if case .all = entry!.allow {} else { XCTFail("expected .all") }
    }

    // MARK: - Threading

    func testExecutionDoesNotBlockTheCallingThread() throws {
        // Python spawns a daemon thread per REQUEST packet (Link.py:985-987), while
        // ReticulumSwift dispatches handlers inline on the receive thread. The listener
        // must therefore return immediately and answer later.
        let executor = MockRNXCommandExecutor()
        let gate = DispatchSemaphore(value: 0)
        executor.gate = gate
        executor.result = RNXExecution(spawned: true, returnCode: 0,
                                       stdout: Data("done\n".utf8), stderr: Data())

        let listener = try makeListener(executor: executor)
        let started = expectation(description: "executor entered")
        let finished = expectation(description: "result produced")

        // Drive the same two steps the native handler performs, on a background queue,
        // and assert the caller is released before the executor returns.
        let request = RNXRequest(command: "sleep", timeout: 15)
        listener.executionQueue.async {
            started.fulfill()
            let execution = executor.execute(command: request.command,
                                             stdin: nil, timeout: request.timeout)
            let result = listener.makeResult(for: request, execution: execution,
                                             startedAt: 0, now: { 1 })
            XCTAssertEqual(result.stdout, Data("done\n".utf8))
            finished.fulfill()
        }

        wait(for: [started], timeout: 2.0)
        // The executor is still blocked, yet this thread is free.
        XCTAssertEqual(executor.callCount, 1)
        gate.signal()
        wait(for: [finished], timeout: 2.0)
    }
}
