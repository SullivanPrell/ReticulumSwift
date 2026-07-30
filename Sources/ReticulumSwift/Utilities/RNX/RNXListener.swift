import Foundation

/// The `rnx -l` half: publishes an `rnx.execute` IN/SINGLE destination, gates callers
/// against an allow-list, runs commands through an injected ``RNXCommandExecutor`` and
/// answers with the fixed 8-element result array.
///
/// Python reference: `RNS/Utilities/rnx.py:63-252` (`listen`, `command_link_established`,
/// `command_link_closed`, `initiator_identified`, `execute_received_command`).
///
/// Two deliberate divergences from Python, both forced by the library and both
/// documented at their call sites:
///
/// 1. **Execution runs off the receive thread.** Python spawns a daemon thread per
///    incoming REQUEST packet (Link.py:985-987); ReticulumSwift dispatches handlers
///    inline. The native handler therefore returns `nil` (send nothing) at once, hands
///    the work to ``executionQueue``, and posts the response envelope itself. The wire
///    format is identical either way: `msgpack([request_id, array8])`.
/// 2. **The allow-list gate is inside the handler.** Python registers with `ALLOW_LIST`
///    and a list of raw 16-byte identity hashes; `Destination.registerNativeRequestHandler`
///    only accepts `[Identity]` objects, which `rnx` never has — an `-a` argument is a
///    hash, and an `Identity` cannot be reconstructed from one. Registering with `.all`
///    and checking `link.remoteIdentity?.hash` here reproduces `ALLOW_LIST` exactly,
///    including the silent drop (no response at all) for an unidentified peer.
public final class RNXListener {

    public enum ListenerError: Error, Equatable {
        /// Python: "Allowed destination length is invalid, must be 32 hexadecimal
        /// characters (16 bytes)." — rnx.py:85. Carries the length actually seen.
        case invalidAllowedHashLength(Int)
        /// Python: "Invalid destination entered. Check your input." — rnx.py:90.
        case invalidAllowedHashHex(String)
        /// The identity loaded from disk carries no private key, so it cannot sign.
        case missingPrivateKey
    }

    // MARK: - State

    /// Python: the `identity` module global.
    public let identity: Identity

    /// Python: `RNS.Destination(identity, IN, SINGLE, "rnx", "execute")` — rnx.py:70.
    public let destination: Destination

    /// Python: `allowed_identity_hashes` — 16-byte **identity** hashes, despite the
    /// "destination" wording in the error messages.
    public private(set) var allowedIdentityHashes: Set<Data>

    /// Python: `allow_all`, set by `-n/--noauth`.
    public private(set) var allowAll: Bool

    /// Log sink. Defaults to `Reticulum.log`, which is what `RNS.log` maps to.
    public var onLog: ((String, Reticulum.LogLevel) -> Void)?

    /// Queue the (blocking) executor runs on. Mirrors Python's per-request daemon thread
    /// (Link.py:985-987). Inject a serial/synchronous queue in tests.
    public var executionQueue: DispatchQueue

    private let transport: Transport
    private let executor: any RNXCommandExecutor

    /// Injected clock, so result timestamps are assertable.
    var now: () -> TimeInterval = { Date().timeIntervalSince1970 }

    public init(identity: Identity,
                transport: Transport,
                executor: any RNXCommandExecutor,
                allowedIdentityHashes: [Data] = [],
                allowAll: Bool = false,
                executionQueue: DispatchQueue = .global(qos: .userInitiated)) throws {
        guard identity.hasPrivateKey else { throw ListenerError.missingPrivateKey }
        self.identity = identity
        self.transport = transport
        self.executor = executor
        self.allowedIdentityHashes = Set(allowedIdentityHashes)
        self.allowAll = allowAll
        self.executionQueue = executionQueue
        self.destination = try Destination(identity: identity,
                                           direction: .in,
                                           kind: .single,
                                           appName: RNXApp.appName,
                                           aspects: [RNXApp.aspect])
    }

    private func log(_ message: String, _ level: Reticulum.LogLevel = .notice) {
        if let onLog { onLog(message, level) } else { Reticulum.log(message, level: level) }
    }

    // MARK: - Registration

    /// Register the destination with `transport`, wire the link callbacks and install the
    /// `"command"` request handler.
    ///
    /// Python gets the transport registration for free — `Destination.__init__` calls
    /// `RNS.Transport.register_destination(self)` for IN destinations (Destination.py:196)
    /// — whereas ReticulumSwift requires it explicitly.
    public func register() {
        transport.register(destination: destination)

        // Python: destination.set_link_established_callback(command_link_established) — rnx.py:116
        destination.setLinkEstablishedCallback { [weak self] link in
            self?.commandLinkEstablished(link)
        }

        // Python: register_request_handler(path="command", ...) — rnx.py:118-130
        destination.registerNativeRequestHandler(path: RNXApp.requestPath,
                                                 allow: .all) { [weak self] _, value, requestID, link, _ in
            self?.handleCommandRequest(value, requestID: requestID, link: link)
            // Always nil: the response is sent from `executionQueue` once the command
            // has actually run, so the receive thread is never blocked.
            return nil
        }
    }

    /// Python: `destination.announce()` — rnx.py:135, skipped under `-b/--no-announce`.
    ///
    /// Goes through `transport.announce(destination:)` rather than `Destination.announce()`,
    /// which silently returns nil when `Reticulum.shared` is nil.
    @discardableResult
    public func announce() throws -> PacketReceipt? {
        try transport.announce(destination: destination)
    }

    // MARK: - Link callbacks

    private func commandLinkEstablished(_ link: Link) {
        // Python: rnx.py:140-143
        link.setRemoteIdentifiedCallback { [weak self] l, identity in
            self?.initiatorIdentified(l, identity)
        }
        link.setLinkClosedCallback { [weak self] l in
            // Python: rnx.py:145-146 — str(link) is prettyhexrep(link_id).
            self?.log("Command link \(RNSUtilities.prettyhexrep(l.linkID ?? Data())) closed")
        }
        log("Command link \(RNSUtilities.prettyhexrep(link.linkID ?? Data())) established")
    }

    private func initiatorIdentified(_ link: Link, _ identity: Identity) {
        // Python: rnx.py:148-153 — belt-and-braces on top of the ALLOW_LIST handler gate.
        log("Initiator of link \(RNSUtilities.prettyhexrep(link.linkID ?? Data())) "
            + "identified as \(RNSUtilities.prettyhexrep(identity.hash))")
        if !allowAll && !allowedIdentityHashes.contains(identity.hash) {
            log("Identity \(RNSUtilities.prettyhexrep(identity.hash)) not allowed, tearing down link")
            try? link.teardown()
        }
    }

    // MARK: - Request handling

    /// Python: `execute_received_command` — rnx.py:155-252, minus the process handling
    /// (which lives behind ``RNXCommandExecutor``).
    private func handleCommandRequest(_ value: MsgPack.Value, requestID: Data, link: Link) {
        // ALLOW_LIST semantics: an unidentified peer, or one not on the list, gets no
        // response at all (Link.py:820-821).
        guard isAllowed(link.remoteIdentity?.hash) else { return }
        guard let request = try? RNXRequest(unpacking: value) else { return }

        let remoteHash = link.remoteIdentity?.hash
        if let remoteHash {
            log("Executing command [\(request.command)] for \(RNSUtilities.prettyhexrep(remoteHash))")
        } else {
            log("Executing command [\(request.command)] for unknown requestor")
        }

        // Python: `result[6] = time.time()` is captured before Popen — rnx.py:174.
        let startedAt = now()
        let executor = self.executor
        executionQueue.async { [weak self] in
            let execution = executor.execute(command: request.command,
                                             stdin: request.stdin,
                                             timeout: request.timeout)
            guard let self else { return }
            let result = self.makeResult(for: request, execution: execution, startedAt: startedAt)
            if let remoteHash {
                self.log("Delivering result of command [\(request.command)] to "
                         + RNSUtilities.prettyhexrep(remoteHash))
            } else {
                self.log("Delivering result of command [\(request.command)] to unknown requestor")
            }
            try? self.deliver(result, requestID: requestID, on: link)
        }
    }

    /// Python's `ALLOW_LIST` predicate: `self.__remote_identity != None and
    /// self.__remote_identity.hash in allowed_list` (Link.py:820-821).
    public func isAllowed(_ identityHash: Data?) -> Bool {
        if allowAll { return true }
        guard let identityHash else { return false }
        return allowedIdentityHashes.contains(identityHash)
    }

    /// Turn an execution into the fixed 8-element result.
    ///
    /// Python builds `[False, None, None, None, None, None, time.time(), None]` and fills
    /// it in (rnx.py:167-241). Two Python crash paths are **not** reproduced, because both
    /// kill the response generator so the client just times out:
    ///
    /// - a nil `stdout`/`stderr` (the terminate-but-still-running branch) makes
    ///   `result[4] = len(stdout)` raise `TypeError` at rnx.py:240 unconditionally. Here a
    ///   nil stream is treated as empty, so a well-formed result is still delivered.
    /// - a negative `--stdout`/`--stderr` reaches Python as `stdout[0:-1]`, dropping the
    ///   last byte. That *is* reproduced (Python slice semantics), because it is harmless
    ///   — `Data.prefix(-1)` would trap, so the index is computed the Python way instead.
    public func makeResult(for request: RNXRequest,
                           execution: RNXExecution,
                           startedAt: TimeInterval,
                           now: (() -> TimeInterval)? = nil) -> RNXResult {
        // Python: the `except` at rnx.py:182 returns immediately with everything nil.
        guard execution.spawned else {
            return RNXResult(executed: false, startedAt: startedAt)
        }

        let clock = now ?? self.now
        let stdout = execution.stdout ?? Data()
        let stderr = execution.stderr ?? Data()

        // Python: rnx.py:218-219 — a concluded timestamp is written ONLY when a timeout
        // was requested AND the deadline had not passed. A request with timeout == nil
        // therefore never gets one, and neither does a command killed by the deadline.
        var concludedAt: TimeInterval?
        if let timeout = request.timeout, !execution.timedOut {
            let t = clock()
            if t < startedAt + timeout { concludedAt = t }
        }

        return RNXResult(
            executed: true,
            returnCode: execution.returnCode,
            stdout: RNXListener.applyLimit(request.stdoutLimit, to: stdout),
            stderr: RNXListener.applyLimit(request.stderrLimit, to: stderr),
            totalStdoutLength: stdout.count,      // Python: result[4] = len(stdout) — pre-truncation
            totalStderrLength: stderr.count,      // Python: result[5] = len(stderr)
            startedAt: startedAt,
            concludedAt: concludedAt
        )
    }

    /// Python: `if limit != None and len(buf) > limit: buf[0:limit] (or b"" when limit == 0)`
    /// — rnx.py:224-238. `limit == nil` short-circuits and the buffer passes through whole.
    static func applyLimit(_ limit: Int?, to buffer: Data) -> Data {
        guard let limit, buffer.count > limit else { return buffer }
        if limit == 0 { return Data() }
        // Python slice semantics, so a negative limit drops that many trailing bytes
        // instead of trapping the way `Data.prefix(-1)` would.
        let end = limit < 0 ? max(0, buffer.count + limit) : min(limit, buffer.count)
        return Data(buffer.prefix(end))
    }

    /// Send `msgpack([request_id, array8])` on `link`.
    ///
    /// Chooses packet-vs-Resource on the **per-link** `mdu`, matching Python's
    /// `len(packed_response) <= self.mdu` (Link.py:848-852). This was the only site in the port
    /// that got it right; `Link.dispatchRequest` used the fixed `Constants.linkMdu` until
    /// `bugs/016` closed the seam, so the two now agree at every MTU rather than only at 500.
    public func deliver(_ result: RNXResult, requestID: Data, on link: Link) throws {
        let body = MsgPack.encode(.array([.bytes(requestID), result.packedValue()]))
        if body.count <= link.mdu {
            try link.send(body, context: .response)
        } else {
            let transfer = ResourceTransfer(link: link)
            try transfer.send(payload: body, requestID: requestID, isResponse: true)
        }
    }

    // MARK: - Allow-list parsing

    /// Python: rnx.py:80-93. Length is checked before content, and both failures print a
    /// message and `exit(1)`.
    public static func parseAllowedHash(_ hex: String) throws -> Data {
        guard hex.count == RNXApp.destinationHexLength else {
            throw ListenerError.invalidAllowedHashLength(hex.count)
        }
        guard let bytes = RNXHex.decode(hex) else {
            throw ListenerError.invalidAllowedHashHex(hex)
        }
        return bytes
    }

    /// Python: rnx.py:94-108 — search `/etc/rnx`, `~/.config/rnx`, `~/.rnx` in order for
    /// `allowed_identities`; first hit wins. Strip every `\r`, split on `\n`, and keep only
    /// lines whose length is exactly 32, so blank lines and comments are tolerated.
    ///
    /// A 32-character non-hex line raises in Python (`bytes.fromhex`) and the utility
    /// prints `str(e)` and exits 1. CPython's wording
    /// ("non-hexadecimal number found in fromhex() arg at position N") cannot be
    /// reproduced, so this throws ``ListenerError/invalidAllowedHashHex(_:)`` instead and
    /// the executable prints its own message. Unlike the spec's sketch this method
    /// therefore `throws`, so that `exit(1)` path survives.
    public static func loadAllowedIdentitiesFile(
        fileManager: FileManager = .default,
        searchPaths: [String] = RNXApp.allowedIdentitiesSearchPaths
    ) throws -> [Data] {
        var found: String?
        for directory in searchPaths {
            let path = DaemonBootstrap.expandTilde(directory)
                + "/" + RNXApp.allowedIdentitiesFileName
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                found = path
                break
            }
        }
        guard let found, let text = try? String(contentsOfFile: found, encoding: .utf8) else {
            return []
        }
        var hashes: [Data] = []
        for line in text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
            guard line.count == RNXApp.destinationHexLength else { continue }
            guard let bytes = RNXHex.decode(line) else {
                throw ListenerError.invalidAllowedHashHex(line)
            }
            hashes.append(bytes)
        }
        return hashes
    }

    // MARK: - Identity

    /// `<configDir>/storage/identities/rnx`.
    /// Python: `RNS.Reticulum.identitypath+"/"+APP_NAME` — rnx.py:53.
    public static func defaultIdentityURL(configDir: URL) -> URL {
        configDir.appendingPathComponent("storage")
            .appendingPathComponent("identities")
            .appendingPathComponent(RNXApp.identityFileName)
    }

    /// Python: `prepare_identity` — rnx.py:50-61. Loads the 64-byte raw private blob if
    /// the file exists, otherwise logs at LOG_INFO, generates one and writes it.
    ///
    /// The parent directory is created first: Python's `Reticulum.__init__` does that
    /// (`os.makedirs(Reticulum.identitypath)`, Reticulum.py:319) but ReticulumSwift's
    /// `Reticulum.start()` only creates `storage/`, so `Identity.toFile` would otherwise
    /// throw `NSFileWriteNoSuchFileError` on the very first run.
    ///
    /// Python's silent overwrite of a corrupt existing file is reproduced.
    public static func loadOrCreateIdentity(
        at url: URL,
        log: ((String, Reticulum.LogLevel) -> Void)? = nil
    ) throws -> Identity {
        if FileManager.default.fileExists(atPath: url.path),
           let loaded = Identity.fromFile(url) {
            return loaded
        }
        let emit = log ?? { message, level in Reticulum.log(message, level: level) }
        emit("No valid saved identity found, creating new...", .info)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let identity = Identity()
        _ = try identity.toFile(url)
        return identity
    }
}
