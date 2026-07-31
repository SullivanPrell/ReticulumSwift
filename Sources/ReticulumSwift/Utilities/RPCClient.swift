import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Client for the RNS instance-control RPC channel — the counterpart of ``RPCServer``.
///
/// Python reference: `RNS/Reticulum.py`, `get_rpc_client()` and every accessor guarded by
/// `if self.is_connected_to_shared_instance:` (`get_interface_stats`, `get_path_table`,
/// `get_rate_table`, `get_link_count`, `get_next_hop`, `drop_path`, …).
///
/// This is what lets `rnstatus`, `rnpath` and `rnprobe` report on a *running* daemon rather
/// than on their own in-process stack: when a shared instance already owns the local ports,
/// the utility attaches to it and asks over RPC instead of standing up a second Transport.
///
/// ## Protocol
///
/// One call per connection: connect → mutual `multiprocessing.connection` handshake
/// (see ``MultiprocessingAuth``) → send one MsgPack-encoded request dict → read one
/// MsgPack-encoded response → close. Every frame is a 4-byte big-endian length followed
/// by that many bytes, matching CPython's `send_bytes` / `recv_bytes`.
///
/// Calls are blocking, which is what a command-line utility wants. Do not call this from
/// a UI thread.
public final class RPCClient {

    // MARK: - Configuration

    /// Default instance-control port.
    /// Python: `Reticulum.local_control_port = 37429`.
    public static let defaultControlPort: UInt16 = 37429

    /// Default shared-instance data port, used by ``isSharedInstanceRunning(host:port:)``.
    /// Python: `Reticulum.shared_instance_port = 37428`.
    public static let defaultSharedInstancePort: UInt16 = 37428

    private let host: String
    private let port: UInt16
    private let authkey: Data
    private let timeout: TimeInterval

    /// - Parameters:
    ///   - host: control-socket host. Python only ever binds `127.0.0.1`.
    ///   - port: control-socket port (`instance_control_port` in the config file).
    ///   - authkey: shared secret — see ``authkey(storagePath:)``.
    ///   - timeout: per-operation socket timeout in seconds.
    public init(host: String = "127.0.0.1",
                port: UInt16 = RPCClient.defaultControlPort,
                authkey: Data,
                timeout: TimeInterval = 5) {
        self.host = host
        self.port = port
        self.authkey = authkey
        self.timeout = timeout
    }

    // MARK: - Auth key derivation

    /// Derive the RPC auth key the way a Reticulum instance does.
    ///
    /// Python: `rpc_key = RNS.Identity.full_hash(RNS.Transport.internal_identity().get_private_key())`,
    /// where the internal identity is loaded from `<storage>/transport_identity`
    /// (`RNS/Transport.py`, `Transport.start`).
    ///
    /// - Parameter storagePath: the instance's storage directory (`~/.reticulum/storage`).
    /// - Throws: ``RPCClientError/noInstanceIdentity`` if the identity file is absent or unreadable.
    public static func authkey(storagePath: URL) throws -> Data {
        let identityURL = StorageInventory.url(.transportIdentity, storage: storagePath)
        guard let identity = try? Identity.read(fromFile: identityURL),
              let privateKey = identity.getPrivateKey() else {
            throw RPCClientError.noInstanceIdentity(identityURL)
        }
        return Identity.fullHash(privateKey)
    }

    /// Build a client for the instance rooted at `storagePath`, deriving its auth key.
    public static func forInstance(storagePath: URL,
                                   host: String = "127.0.0.1",
                                   port: UInt16 = RPCClient.defaultControlPort,
                                   timeout: TimeInterval = 5) throws -> RPCClient {
        RPCClient(host: host, port: port, authkey: try authkey(storagePath: storagePath), timeout: timeout)
    }

    // MARK: - Shared-instance detection

    /// Whether something is already listening on the shared-instance port.
    ///
    /// Python decides this by *trying to become* the shared instance and falling back to
    /// client mode when the bind fails (`Reticulum.__start_local_interface`). A utility
    /// that only wants to read status does not want to bind anything, so it probes instead.
    public static func isSharedInstanceRunning(host: String = "127.0.0.1",
                                               port: UInt16 = RPCClient.defaultSharedInstancePort,
                                               timeout: TimeInterval = 1) -> Bool {
        guard let fd = try? openSocket(host: host, port: port, timeout: timeout) else { return false }
        close(fd)
        return true
    }

    // MARK: - Raw call

    /// Perform one RPC call and return the decoded response.
    ///
    /// - Parameter request: the request dict, e.g. `.map([(.string("get"), .string("path_table"))])`.
    public func call(_ request: MsgPack.Value) throws -> MsgPack.Value {
        let fd = try RPCClient.openSocket(host: host, port: port, timeout: timeout)
        defer { close(fd) }

        try handshake(fd)
        try sendFrame(fd, MsgPack.encode(request))
        let response = try receiveFrame(fd)
        return try MsgPack.decode(response)
    }

    /// Convenience for `{"get": <path>, ...extra}` calls.
    public func get(_ path: String, extra: [(String, MsgPack.Value)] = []) throws -> MsgPack.Value {
        var pairs: [(MsgPack.Value, MsgPack.Value)] = [(.string("get"), .string(path))]
        for (key, value) in extra { pairs.append((.string(key), value)) }
        return try call(.map(pairs))
    }

    /// Convenience for `{"drop": <target>, ...extra}` calls.
    @discardableResult
    public func drop(_ target: String, extra: [(String, MsgPack.Value)] = []) throws -> MsgPack.Value {
        var pairs: [(MsgPack.Value, MsgPack.Value)] = [(.string("drop"), .string(target))]
        for (key, value) in extra { pairs.append((.string(key), value)) }
        return try call(.map(pairs))
    }

    // MARK: - Typed accessors (mirroring Python's Reticulum RPC client methods)

    /// Python: `get_interface_stats()` → `{"get": "interface_stats"}`.
    public func interfaceStats() throws -> MsgPack.Value { try get("interface_stats") }

    /// Python: `get_path_table(max_hops=None)` → `{"get": "path_table", "max_hops": max_hops}`.
    public func pathTable(maxHops: UInt8? = nil) throws -> MsgPack.Value {
        try get("path_table", extra: [("max_hops", maxHops.map { .uint(UInt64($0)) } ?? .nil)])
    }

    /// Python: `get_rate_table()`.
    public func rateTable() throws -> MsgPack.Value { try get("rate_table") }

    /// Python: `get_link_count()`.
    public func linkCount() throws -> Int? { try get("link_count").asInt }

    /// Python: `get_next_hop(destination_hash)`.
    public func nextHop(destinationHash: Data) throws -> Data? {
        if case .bytes(let hop) = try get("next_hop", extra: [("destination_hash", .bytes(destinationHash))]) {
            return hop
        }
        return nil
    }

    /// Python: `get_next_hop_if_name(destination_hash)`.
    public func nextHopInterfaceName(destinationHash: Data) throws -> String? {
        if case .string(let name) = try get("next_hop_if_name", extra: [("destination_hash", .bytes(destinationHash))]) {
            return name
        }
        return nil
    }

    /// Python: `get_first_hop_timeout(destination_hash)`.
    public func firstHopTimeout(destinationHash: Data) throws -> TimeInterval? {
        try get("first_hop_timeout", extra: [("destination_hash", .bytes(destinationHash))]).asDouble
    }

    /// Python: `get_packet_rssi(packet_hash)`.
    public func packetRSSI(packetHash: Data) throws -> Double? {
        try get("packet_rssi", extra: [("packet_hash", .bytes(packetHash))]).asDouble
    }

    /// Python: `get_packet_snr(packet_hash)`.
    public func packetSNR(packetHash: Data) throws -> Double? {
        try get("packet_snr", extra: [("packet_hash", .bytes(packetHash))]).asDouble
    }

    /// Python: `get_packet_q(packet_hash)`.
    public func packetQ(packetHash: Data) throws -> Double? {
        try get("packet_q", extra: [("packet_hash", .bytes(packetHash))]).asDouble
    }

    /// Python: `get_blackholed_identities()` — the whole `Transport.blackholed_identities`
    /// dict, keyed by identity hash, each value carrying `source`, `until` and `reason`.
    public func blackholedIdentities() throws -> [Data: Transport.BlackholeEntry] {
        guard case .map(let pairs) = try get("blackholed_identities") else { return [:] }
        var result: [Data: Transport.BlackholeEntry] = [:]
        for (key, value) in pairs {
            guard case .bytes(let hash) = key else { continue }
            let fields = value.asDictionary ?? [:]
            result[hash] = Transport.BlackholeEntry(
                source: fields["source"]?.asData,
                until:  fields["until"]?.asDouble,
                reason: fields["reason"]?.asString
            )
        }
        return result
    }

    /// Python: `is_blackholed(identity_hash)`.
    public func isBlackholed(identityHash: Data) throws -> Bool {
        if case .bool(let flag) = try get("is_blackholed", extra: [("identity_hash", .bytes(identityHash))]) {
            return flag
        }
        return false
    }

    /// Python: `drop_path(destination_hash)` — returns whether a path was actually removed.
    @discardableResult
    public func dropPath(destinationHash: Data) throws -> Bool {
        try drop("path", extra: [("destination_hash", .bytes(destinationHash))]).asBool ?? false
    }

    /// Python: `drop_all_via(transport_hash)` — returns the number of paths dropped.
    @discardableResult
    public func dropAllVia(transportHash: Data) throws -> Int {
        try drop("all_via", extra: [("destination_hash", .bytes(transportHash))]).asInt ?? 0
    }

    /// Python: `drop_announce_queues()`.
    public func dropAnnounceQueues() throws {
        try drop("announce_queues")
    }

    /// Python: `blackhole_identity(identity_hash, until=None, reason=None)`.
    public func blackholeIdentity(_ identityHash: Data, until: TimeInterval? = nil, reason: String? = nil) throws {
        var pairs: [(MsgPack.Value, MsgPack.Value)] = [(.string("blackhole_identity"), .bytes(identityHash))]
        pairs.append((.string("until"),  until.map { .double($0) } ?? .nil))
        pairs.append((.string("reason"), reason.map { .string($0) } ?? .nil))
        _ = try call(.map(pairs))
    }

    /// Python: `unblackhole_identity(identity_hash)`.
    public func unblackholeIdentity(_ identityHash: Data) throws {
        _ = try call(.map([(.string("unblackhole_identity"), .bytes(identityHash))]))
    }

    // MARK: - Handshake

    /// Run CPython's mutual authentication: answer the peer's challenge, then issue our own.
    ///
    /// Python `multiprocessing.connection.Client`:
    /// ```
    /// answer_challenge(c, authkey)
    /// deliver_challenge(c, authkey)
    /// ```
    private func handshake(_ fd: Int32) throws {
        // --- answer_challenge -------------------------------------------------
        let challenge = try receiveFrame(fd)
        let prefix = MultiprocessingAuth.challengePrefix
        guard challenge.count > prefix.count, challenge.prefix(prefix.count) == prefix else {
            throw RPCClientError.handshakeFailed("peer did not send #CHALLENGE#")
        }
        let message = Data(challenge.dropFirst(prefix.count))
        let response = try MultiprocessingAuth.createResponse(authkey: authkey, message: message)
        try sendFrame(fd, response)

        let welcome = try receiveFrame(fd)
        guard welcome == MultiprocessingAuth.welcomeMessage else {
            throw RPCClientError.authenticationFailed
        }

        // --- deliver_challenge ------------------------------------------------
        let ourMessage = MultiprocessingAuth.makeChallengeMessage(digest: .sha256)
        try sendFrame(fd, prefix + ourMessage)
        let theirResponse = try receiveFrame(fd)
        guard MultiprocessingAuth.verifyChallenge(authkey: authkey,
                                                  message: ourMessage,
                                                  response: theirResponse) else {
            try? sendFrame(fd, MultiprocessingAuth.failureMessage)
            throw RPCClientError.authenticationFailed
        }
        try sendFrame(fd, MultiprocessingAuth.welcomeMessage)
    }

    // MARK: - Socket plumbing

    private static func openSocket(host: String, port: UInt16, timeout: TimeInterval) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var info: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &info)
        guard status == 0, let first = info else { throw RPCClientError.connectionFailed(host, port) }
        defer { freeaddrinfo(info) }

        var candidate: UnsafeMutablePointer<addrinfo>? = first
        while let entry = candidate {
            let fd = socket(entry.pointee.ai_family, entry.pointee.ai_socktype, entry.pointee.ai_protocol)
            if fd >= 0 {
                setTimeout(fd, timeout)
                if connect(fd, entry.pointee.ai_addr, entry.pointee.ai_addrlen) == 0 { return fd }
                close(fd)
            }
            candidate = entry.pointee.ai_next
        }
        throw RPCClientError.connectionFailed(host, port)
    }

    private static func setTimeout(_ fd: Int32, _ seconds: TimeInterval) {
        var tv = timeval(tv_sec: Int(seconds),
                         tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Python `Connection._send_bytes`: 4-byte big-endian length, then the payload.
    private func sendFrame(_ fd: Int32, _ payload: Data) throws {
        var header = Int32(payload.count).bigEndian
        var frame = Data(bytes: &header, count: 4)
        frame.append(payload)
        try writeAll(fd, frame)
    }

    /// Python `Connection._recv_bytes`: read the 4-byte header, then that many bytes.
    /// A header of `-1` introduces an 8-byte length for payloads above 2 GiB.
    private func receiveFrame(_ fd: Int32) throws -> Data {
        let header = try readExactly(fd, 4)
        let signed = header.withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
        var length = Int(signed)
        if signed == -1 {
            let wide = try readExactly(fd, 8)
            length = Int(wide.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian })
        }
        guard length >= 0, length <= 64 * 1_048_576 else {
            throw RPCClientError.malformedResponse("implausible frame length \(length)")
        }
        if length == 0 { return Data() }
        return try readExactly(fd, length)
    }

    private func writeAll(_ fd: Int32, _ data: Data) throws {
        var sent = 0
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            while sent < data.count {
                let n = send(fd, base.advanced(by: sent), data.count - sent, 0)
                if n > 0 { sent += n; continue }
                if n < 0 && errno == EINTR { continue }
                throw RPCClientError.connectionClosed
            }
        }
    }

    private func readExactly(_ fd: Int32, _ count: Int) throws -> Data {
        var out = Data(count: count)
        var received = 0
        try out.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            while received < count {
                let n = recv(fd, base.advanced(by: received), count - received, 0)
                if n > 0 { received += n; continue }
                if n < 0 && errno == EINTR { continue }
                throw RPCClientError.connectionClosed
            }
        }
        return out
    }
}

// MARK: - Errors

public enum RPCClientError: Error, CustomStringConvertible {
    /// No `transport_identity` in the given storage directory, so no auth key can be derived.
    case noInstanceIdentity(URL)
    /// Could not open a TCP connection to the control socket.
    case connectionFailed(String, UInt16)
    /// The peer closed the connection mid-exchange.
    case connectionClosed
    /// The peer's greeting did not follow the `multiprocessing.connection` protocol.
    case handshakeFailed(String)
    /// The shared secret did not match — usually a different instance's storage directory.
    case authenticationFailed
    /// The response was not decodable.
    case malformedResponse(String)

    public var description: String {
        switch self {
        case .noInstanceIdentity(let url):
            return "No instance identity at \(url.path) — is a Reticulum instance configured here?"
        case .connectionFailed(let host, let port):
            return "Could not connect to instance control socket at \(host):\(port)"
        case .connectionClosed:
            return "Instance closed the control connection unexpectedly"
        case .handshakeFailed(let detail):
            return "Instance control handshake failed: \(detail)"
        case .authenticationFailed:
            return "Instance control authentication failed — auth key mismatch"
        case .malformedResponse(let detail):
            return "Malformed response from instance: \(detail)"
        }
    }
}
