import Foundation
import Network
import CryptoKit

/// Python `multiprocessing.connection`-compatible RPC server.
///
/// Handles the HMAC-MD5 challenge-response handshake and responds to every
/// RPC call that Python RNS clients make over port 37429.
///
/// ## Wire protocol
/// Authentication uses `multiprocessing.connection`'s HMAC-MD5 mutual
/// challenge-response (the same in every RNS version).  The RPC payloads
/// (both call and response) are **MsgPack**-encoded using Python's
/// `RNS.vendor.umsgpack` (RNS ≥ 1.3.0).  Each payload is preceded by a
/// 4-byte big-endian signed-int length — Python `send_bytes` / `recv_bytes`.
///
/// Protocol: each connection is one-shot — one call, one response, close.
public final class RPCServer {
    private let port: UInt16
    private let authkey: Data
    private var listener: NWListener?
    // Serial (not .concurrent): RPC connection handlers touch the Transport,
    // whose accessors are individually synchronized but not mutually atomic.
    // Serializing connections keeps RPC handlers from racing each other; each is
    // a one-shot low-volume management call, so throughput is a non-issue.
    private let queue = DispatchQueue(label: "ReticulumSwift.RPCServer")

    /// Live transport reference — set by `Reticulum.startRPC` after creation.
    /// Weak to avoid a retain cycle (Transport → Reticulum → RPCServer → Transport).
    public weak var transport: Transport?

    private static let challengePrefix = MultiprocessingAuth.challengePrefix
    private static let welcomeMessage  = MultiprocessingAuth.welcomeMessage
    private static let failureMessage  = MultiprocessingAuth.failureMessage

    public init(port: UInt16, authkey: Data) {
        self.port = port
        self.authkey = authkey
    }

    public func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw RPCError.invalidPort
        }
        // A loopback control socket, so it takes the shared-instance option set — `TCP_NODELAY`,
        // no keepalive — the same one `LocalInterface` uses. Python's RPC listener is a
        // `multiprocessing.connection.Listener` and sets nothing, but this is still a socket this
        // port opens, and it had the same defect as the rest: `.tcp` meant Nagle held small
        // control frames behind the delayed-ACK timer. Found by the construction-site guard;
        // not in `bugs/023` as filed.
        //
        // "Loopback" is a property of the parameters, not of intent: Python constructs its
        // listener on `("127.0.0.1", port)` (`Reticulum.py:352`, `:359`), and parameters without
        // a required local endpoint bind the wildcard — which put this authenticated management
        // socket on every network the host was attached to. The port travels inside the
        // endpoint, so no `on:` argument here.
        let listener = try NWListener(
            using: RNSSocketOptions.localListenerParameters(port: nwPort).parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.handleConnection(conn) }

        // Wait for the listener to be ready, and throw if it fails.
        //
        // `NWListener.start(queue:)` returns before the bind is attempted and reports the result
        // asynchronously through `stateUpdateHandler`. With no handler set, a listener that never
        // bound still reached the log line below — so a daemon whose control port was taken
        // announced "RPC server started on port N", ran normally, and answered every `rnstatus`,
        // `rnpath`, `rnprobe`, `rnid -r` and `rnx` with "Could not connect to instance control
        // socket". A component reporting success it did not achieve; `bugs/040`.
        //
        // Python raises here — `SocketListener.__init__` does `except OSError: … raise` — and
        // `rnsd` exits rather than running without a control socket. Blocking until the state is
        // known also means a caller may connect as soon as `start()` returns, instead of racing
        // the bind.
        let settled = DispatchSemaphore(value: 0)
        var failure: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                settled.signal()
            case .failed(let error), .waiting(let error):
                // `.waiting` is where an address conflict surfaces: the framework holds the
                // listener in that state and retries, so treating it as "not yet ready" would
                // hang for the settle timeout and then report success anyway.
                failure = error
                settled.signal()
            case .cancelled:
                settled.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)

        if settled.wait(timeout: .now() + RPCServer.bindTimeout) == .timedOut {
            listener.cancel()
            self.listener = nil
            throw RPCError.listenerFailed(nil)
        }
        if let failure {
            listener.cancel()
            self.listener = nil
            throw RPCError.listenerFailed(failure)
        }
        Reticulum.log("RPC server started on port \(port)", level: .info)
    }

    /// How long `start()` waits for the listener to reach a terminal state. Generous: this is a
    /// loopback bind, so anything approaching it means the framework is not going to answer.
    private static let bindTimeout: DispatchTimeInterval = .seconds(5)

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection lifecycle

    private func handleConnection(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:  self?.deliverChallenge(conn)
            case .failed: conn.cancel()
            default:      break
            }
        }
        conn.start(queue: queue)
    }

    private func deliverChallenge(_ conn: NWConnection) {
        // Modern (CPython ≥ 3.12) challenge: "{sha256}" + 40 random bytes. Legacy
        // clients (≤ 3.11) answer this with a bare HMAC-MD5 over the whole message,
        // which `verifyChallenge` also accepts — so one challenge serves both.
        let message = MultiprocessingAuth.makeChallengeMessage(digest: .sha256)
        let challenge = RPCServer.challengePrefix + message

        sendBytes(challenge, over: conn) { [weak self] error in
            if let error {
                Reticulum.log("RPC challenge send failed: \(error)", level: .error)
                conn.cancel(); return
            }
            self?.receiveBytes(from: conn) { digest, err in
                guard let self, let digest, err == nil else { conn.cancel(); return }
                if MultiprocessingAuth.verifyChallenge(authkey: self.authkey,
                                                       message: message,
                                                       response: digest) {
                    self.sendBytes(RPCServer.welcomeMessage, over: conn) { [weak self] _ in
                        Reticulum.log("RPC client auth OK from \(conn.endpoint)", level: .debug)
                        self?.answerChallenge(conn)
                    }
                } else {
                    self.sendBytes(RPCServer.failureMessage, over: conn) { _ in
                        Reticulum.log("RPC auth failed from \(conn.endpoint)", level: .warning)
                        conn.cancel()
                    }
                }
            }
        }
    }

    // MARK: - Mutual authentication (step 2 of 2)

    // Python's connection.Client runs: answer_challenge (client proves itself to server)
    // then deliver_challenge (client verifies the server). We must respond to that second
    // challenge or every RPC call fails with AuthenticationError before it starts.
    private func answerChallenge(_ conn: NWConnection) {
        receiveBytes(from: conn) { [weak self] challengeMsg, err in
            guard let self, let challengeMsg, err == nil else { conn.cancel(); return }
            let prefix = RPCServer.challengePrefix
            // The client's challenge is 20 raw bytes on CPython ≤ 3.11 and
            // "{sha256}" + 40 bytes on ≥ 3.12; accept either, and let
            // `createResponse` pick the matching digest and reply framing.
            guard challengeMsg.count > prefix.count,
                  challengeMsg.prefix(prefix.count) == prefix else {
                Reticulum.log("RPC: bad client challenge (\(challengeMsg.count) bytes)", level: .warning)
                conn.cancel(); return
            }
            let nonce = Data(challengeMsg.dropFirst(prefix.count))
            guard let digest = try? MultiprocessingAuth.createResponse(authkey: self.authkey, message: nonce) else {
                Reticulum.log("RPC: unsupported client challenge format", level: .warning)
                conn.cancel(); return
            }
            self.sendBytes(digest, over: conn) { [weak self] error in
                if let error {
                    Reticulum.log("RPC: digest send failed: \(error)", level: .error)
                    conn.cancel(); return
                }
                self?.receiveBytes(from: conn) { [weak self] response, err in
                    guard let response, err == nil else { conn.cancel(); return }
                    if response == RPCServer.welcomeMessage {
                        Reticulum.log("RPC mutual auth OK from \(conn.endpoint)", level: .debug)
                        self?.readCall(conn)
                    } else {
                        Reticulum.log("RPC: server auth rejected by client", level: .warning)
                        conn.cancel()
                    }
                }
            }
        }
    }

    // MARK: - Call dispatch

    private func readCall(_ conn: NWConnection) {
        conn.receive(exactly: 4) { [weak self] data, _, isComplete, error in
            if isComplete || error != nil { conn.cancel(); return }
            guard let data, data.count == 4 else { conn.cancel(); return }
            let length = Int(data.withUnsafeBytes { $0.load(as: Int32.self).bigEndian })
            guard length > 0, length < 1_048_576 else { conn.cancel(); return }

            conn.receive(exactly: length) { [weak self] payload, _, _, err in
                guard let self, let payload, err == nil else { conn.cancel(); return }
                let response = self.respond(to: payload)
                self.sendBytes(response, over: conn) { _ in conn.cancel() }
            }
        }
    }

    // MARK: - MsgPack dispatch
    //
    // Calls arrive as MsgPack-encoded dicts (RNS ≥ 1.3.0 uses umsgpack for all
    // RPC payloads).  Responses are also MsgPack-encoded.

    /// Exposed `internal` so unit tests can call it directly via `@testable import`.
    func respond(to payload: Data) -> Data {
        guard let call = try? MsgPack.decode(payload),
              case .map(let pairs) = call else {
            Reticulum.log("RPC: failed to decode MsgPack payload (\(payload.count) bytes) \(payload.prefix(16).map { String(format: "%02x", $0) }.joined())", level: .warning)
            return msgpack(.nil)
        }

        // Build lookup dict from the map pairs
        var kv: [String: MsgPack.Value] = [:]
        for (k, v) in pairs {
            if case .string(let s) = k { kv[s] = v }
        }

        // Calls using {"get": "<name>", ...}
        if let getKey = kv["get"], case .string(let path) = getKey {
            return respondGet(path: path, kv: kv)
        }

        // Drop calls — {"drop": "<target>", ...}
        if let dropKey = kv["drop"], case .string(let target) = dropKey {
            return respondDrop(target: target, kv: kv)
        }

        // destination_data: used / retain / unretain
        if let ddKey = kv["destination_data"], case .string(let op) = ddKey {
            let hash = binValue(kv["destination_hash"])
            switch op {
            case "used":
                if let t = transport, let h = hash {
                    return msgpack(.bool(t.markDestinationUsed(h)))
                }
                return msgpack(.bool(false))
            case "retain":
                if let t = transport, let h = hash {
                    return msgpack(.bool(t.retainDestinationData(h)))
                }
                return msgpack(.bool(false))
            case "unretain":
                if let t = transport, let h = hash {
                    return msgpack(.bool(t.unretainDestinationData(h)))
                }
                return msgpack(.bool(false))
            default:
                return msgpack(.nil)
            }
        }

        // identity_data: retain
        if let idKey = kv["identity_data"], case .string(let op) = idKey {
            if op == "retain" {
                if let t = transport, let h = binValue(kv["identity_hash"]) {
                    return msgpack(.bool(t.retainIdentity(h)))
                }
            }
            return msgpack(.bool(false))
        }

        // Python: {"unblackhole_identity": identity_hash}
        // The hash is the VALUE of the "unblackhole_identity" key.
        if let ubhKey = kv["unblackhole_identity"] {
            // Python's rpc_loop returns the call's value verbatim (Reticulum.py:1234):
            // True lifted, None not blackholed, False rejected. `rnpath -U` prints a
            // different message for each, so replying .nil unconditionally would make
            // every success read as "not blackholed" — in both directions.
            if let t = transport, let hash = binValue(ubhKey) {
                return msgpack(triState(t.unblackholeIdentity(hash)))
            }
            return msgpack(.nil)
        }

        // Python: {"blackhole_identity": identity_hash, "until": until, "reason": reason}
        // The hash is the VALUE of the "blackhole_identity" key.
        if let bhKey = kv["blackhole_identity"] {
            if let t = transport, let hash = binValue(bhKey) {
                // Extract optional until timestamp
                let until: TimeInterval? = {
                    guard let u = kv["until"] else { return nil }
                    if case .double(let d) = u { return d }
                    if case .int(let i) = u, i > 0 { return Double(i) }
                    if case .uint(let u) = u, u > 0 { return Double(u) }
                    return nil
                }()
                // Extract optional reason string
                let reason: String? = {
                    guard let r = kv["reason"], case .string(let s) = r else { return nil }
                    return s
                }()
                // Python: Reticulum.py:1230 returns the tri-state verbatim — see the
                // unblackhole_identity note above.
                return msgpack(triState(t.blackholeIdentity(hash, until: until, reason: reason)))
            }
            return msgpack(.nil)
        }

        Reticulum.log("RPC: unrecognised call (\(payload.count) bytes) \(payload.prefix(32).map { String(format: "%02x", $0) }.joined())", level: .warning)
        return msgpack(.nil)
    }

    // MARK: - "get" handler

    private func respondGet(path: String, kv: [String: MsgPack.Value]) -> Data {
        switch path {
        case "interface_stats":
            guard let t = transport else { return msgpack(InterfaceStatsPayload.empty) }
            return msgpack(InterfaceStatsPayload.build(t))

        case "path_table":
            guard let t = transport else { return msgpack(.array([])) }
            let maxHops: UInt8? = {
                guard let v = kv["max_hops"], case .uint(let n) = v else { return nil }
                return UInt8(min(n, 255))
            }()
            return msgpack(buildPathTable(t, maxHops: maxHops))

        case "rate_table":
            guard let t = transport else { return msgpack(.array([])) }
            return msgpack(buildRateTable(t))

        case "link_count":
            guard let t = transport else { return msgpack(.int(0)) }
            return msgpack(.int(Int64(t.getLinkCount())))

        case "next_hop":
            if let t = transport, let hash = binValue(kv["destination_hash"]),
               let hop = t.nextHop(to: hash) {
                return msgpack(.bytes(hop))
            }
            return msgpack(.nil)

        case "next_hop_if_name":
            // Python: `str(RNS.Transport.next_hop_interface(destination))` — the
            // interface's `__str__` (Swift: `displayName`, NOT `Interface.name`), and the
            // literal string "None" when there is no interface. A Python `rnprobe` tests
            // the response against the *string* "None", so answering msgpack nil made it
            // print " on None".
            if let t = transport, let hash = binValue(kv["destination_hash"]),
               let iface = t.nextHopInterface(for: hash) {
                return msgpack(.string(iface.displayName))
            }
            return msgpack(.string("None"))

        case "first_hop_timeout":
            if let t = transport, let hash = binValue(kv["destination_hash"]) {
                return msgpack(.double(t.firstHopTimeout(for: hash)))
            }
            return msgpack(.double(Transport.pathRequestTimeout))

        case "blackholed_identities":
            // Python returns `Transport.blackholed_identities` verbatim, which maps each
            // identity hash to the full entry dict {"source", "until", "reason"}
            // (Transport.py `blackhole_identity`). rnpath reads all three fields off it,
            // so emitting a bare `true` here would break `rnpath -b`.
            guard let t = transport else { return msgpack(.map([])) }
            t.blackholeLock.lock()
            let entries = t.blackholedIdentities
            t.blackholeLock.unlock()
            let pairs: [(MsgPack.Value, MsgPack.Value)] = entries.map { hash, entry in
                (.bytes(hash), .map([
                    (.string("source"), entry.source.map { .bytes($0) } ?? .nil),
                    (.string("until"),  entry.until.map  { .double($0) } ?? .nil),
                    (.string("reason"), entry.reason.map { .string($0) } ?? .nil),
                ]))
            }
            return msgpack(.map(pairs))

        case "is_blackholed":
            if let t = transport, let hash = binValue(kv["identity_hash"]) {
                return msgpack(.bool(t.isBlackholed(hash)))
            }
            return msgpack(.bool(false))

        case "packet_rssi":
            if let t = transport, let hash = binValue(kv["packet_hash"]),
               let rssi = t.getPacketRssi(packetHash: hash) {
                // Python's RSSI is an integer (`byte - RSSI_OFFSET`, RNodeInterface.py:878)
                // and rnprobe renders it with `str()`, so a float here would print
                // "[RSSI -73.0 dBm]" where Python prints "[RSSI -73 dBm]". SNR and quality
                // below stay floats, matching RNodeInterface.py:880 and :890.
                return msgpack(.int(Int64(rssi.rounded())))
            }
            return msgpack(.nil)

        case "packet_snr":
            if let t = transport, let hash = binValue(kv["packet_hash"]),
               let snr = t.getPacketSnr(packetHash: hash) {
                return msgpack(.double(Double(snr)))
            }
            return msgpack(.nil)

        case "packet_q":
            if let t = transport, let hash = binValue(kv["packet_hash"]),
               let q = t.getPacketQ(packetHash: hash) {
                return msgpack(.double(Double(q)))
            }
            return msgpack(.nil)

        default:
            Reticulum.log("RPC get: unknown path '\(path)'", level: .warning)
            return msgpack(.nil)
        }
    }

    // MARK: - "drop" handler

    private func respondDrop(target: String, kv: [String: MsgPack.Value]) -> Data {
        switch target {
        case "path":
            // Python returns the bool from Transport.expire_path (Reticulum.py:1519),
            // which rnpath prints as "Path to <hash> was dropped" vs "No path known".
            if let t = transport, let hash = binValue(kv["destination_hash"]) {
                return msgpack(.bool(t.expirePath(for: hash)))
            }
            return msgpack(.bool(false))

        case "all_via":
            if let t = transport, let hash = binValue(kv["destination_hash"]) {
                return msgpack(.int(Int64(t.dropAllPaths(via: hash))))
            }
            return msgpack(.int(0))

        case "announce_queues":
            transport?.dropAnnounceQueues()
            return msgpack(.nil)

        default:
            return msgpack(.nil)
        }
    }

    // MARK: - path_table builder

    private func buildPathTable(_ t: Transport, maxHops: UInt8?) -> MsgPack.Value {
        let entries = t.getPathTable(maxHops: maxHops)
        let values: [MsgPack.Value] = entries.map { entry in
            .map([
                (.string("hash"),      .bytes(entry.destinationHash)),
                (.string("timestamp"), .double(entry.lastHeard.timeIntervalSince1970)),
                (.string("via"),       .bytes(entry.via)),
                (.string("hops"),      .int(Int64(entry.hops))),
                (.string("expires"),   .double(entry.expires.timeIntervalSince1970)),
                (.string("interface"), .string(entry.interfaceName)),
            ])
        }
        return .array(values)
    }

    // MARK: - rate_table builder

    private func buildRateTable(_ t: Transport) -> MsgPack.Value {
        let entries = t.getRateTable()
        let values: [MsgPack.Value] = entries.map { entry in
            .map([
                (.string("hash"),            .bytes(entry.destinationHash)),
                (.string("last"),            .double(entry.last)),
                (.string("rate_violations"), .int(Int64(entry.rateViolations))),
                (.string("blocked_until"),   .double(entry.blockedUntil)),
                (.string("timestamps"),      .array(entry.timestamps.map { .double($0) })),
            ])
        }
        return .array(values)
    }

    // MARK: - Helpers

    /// Encode a MsgPack value into a length-prefixed byte blob ready to send.
    private func msgpack(_ value: MsgPack.Value) -> Data {
        MsgPack.encode(value)
    }

    /// Encode Python's `True` / `None` / `False` tri-state, which the blackhole calls
    /// return and `rnpath -B` / `-U` branch on.
    private func triState(_ value: Bool?) -> MsgPack.Value {
        value.map { MsgPack.Value.bool($0) } ?? .nil
    }

    /// Extract a binary (bytes) value from a MsgPack.Value, or nil.
    private func binValue(_ v: MsgPack.Value?) -> Data? {
        guard let v else { return nil }
        if case .bytes(let d) = v { return d }
        return nil
    }

    // MARK: - Wire helpers

    private func sendBytes(_ bytes: Data, over conn: NWConnection, completion: @escaping (Error?) -> Void) {
        var length = Int32(bytes.count).bigEndian
        let header = Data(bytes: &length, count: 4)
        conn.send(content: header + bytes, completion: .contentProcessed { completion($0) })
    }

    private func receiveBytes(from conn: NWConnection, completion: @escaping (Data?, Error?) -> Void) {
        conn.receive(exactly: 4) { lengthData, _, _, error in
            if let error { completion(nil, error); return }
            guard let lengthData, lengthData.count == 4 else {
                completion(nil, RPCError.invalidProtocol); return
            }
            let length = Int(lengthData.withUnsafeBytes { $0.load(as: Int32.self).bigEndian })
            guard length > 0, length < 65536 else {
                completion(nil, RPCError.invalidProtocol); return
            }
            conn.receive(exactly: length) { payload, _, _, error in completion(payload, error) }
        }
    }

    public enum RPCError: Error {
        case invalidPort
        case invalidProtocol
        /// The listener never reached `.ready`. Carries the framework's error when there was
        /// one, and `nil` when the state simply never settled (`bugs/040`).
        case listenerFailed(Error?)
    }
}

private extension NWConnection {
    func receive(exactly count: Int, completion: @escaping (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void) {
        self.receive(minimumIncompleteLength: count, maximumLength: count, completion: completion)
    }
}
