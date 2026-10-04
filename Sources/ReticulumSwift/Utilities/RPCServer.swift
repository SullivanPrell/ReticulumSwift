//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import CryptoKit
import Darwin
import Foundation

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
/// 4-byte big-endian signed-int length—Python `send_bytes` / `recv_bytes`.
///
/// Protocol: each connection is one-shot—one call, one response, close.
public final class RPCServer {
  private let port: UInt16
  private let authkey: Data
  /// Reads the listening descriptor; its cancel handler closes the descriptor.
  private var acceptSource: DispatchSourceRead?
  private var listenFD: Int32 = -1
  // Serial (not .concurrent): RPC call handlers touch the Transport,
  // whose accessors are individually synchronized but not mutually atomic.
  // Serializing calls keeps RPC handlers from racing each other; each is
  // a one-shot low-volume management call, so throughput is a non-issue.
  private let queue = DispatchQueue(label: "ReticulumSwift.RPCServer")
  /// Runs each connection's blocking I/O, so a stalled client holds only its own thread.
  private let connectionQueue = DispatchQueue(
    label: "ReticulumSwift.RPCServer.connection", attributes: .concurrent)

  /// How long a connection's read or write may block before the connection is dropped.
  private static let ioTimeoutSeconds = 10

  /// The listening descriptor, for tests that read its options back with `getsockopt`.
  var listeningDescriptorForTesting: Int32 { listenFD }

  /// Live transport reference—set by `Reticulum.startRPC` after creation.
  ///
  /// Weak to avoid a retain cycle (Transport → Reticulum → RPCServer → Transport).
  public weak var transport: Transport?

  /// The instance whose interfaces `manage` calls attach, detach and reload.
  ///
  /// Weak for the same reason as `transport`. Without one, a `manage` call is answered with
  /// `nil`.
  public weak var reticulum: Reticulum?

  private static let challengePrefix = MultiprocessingAuth.challengePrefix
  private static let welcomeMessage = MultiprocessingAuth.welcomeMessage
  private static let failureMessage = MultiprocessingAuth.failureMessage

  /// Creates a server bound to `port` and authenticated with `authkey`.
  public init(port: UInt16, authkey: Data) {
    self.port = port
    self.authkey = authkey
  }

  /// Starts listening for control connections on `127.0.0.1:port`.
  ///
  /// A BSD socket with `SO_REUSEADDR`, bound to loopback, as Python's control listener is
  /// (`Reticulum.py:359`, `:366`; CPython `multiprocessing/connection.py:638-651`). That bind
  /// conflicts only with a socket on 127.0.0.1 or the wildcard. `NWListener` refuses a port
  /// held on any local address, including one that `bind(("127.0.0.1", 0))` has just reported
  /// free (`bugs/040`).
  ///
  /// The socket accepts connections once this returns.
  ///
  /// - Throws: `RPCError.listenerFailed` carrying the `POSIXError` when the socket can't be
  ///   bound or listened on, where Python raises the `OSError`.
  public func start() throws {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw RPCError.listenerFailed(Self.currentPOSIXError()) }
    var one: Int32 = 1
    let size = socklen_t(MemoryLayout<Int32>.size)
    Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, size)
    Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, size)

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    Darwin.inet_aton("127.0.0.1", &addr.sin_addr)
    let bound = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0, Darwin.listen(fd, 16) == 0 else {
      let error = Self.currentPOSIXError()
      Darwin.close(fd)
      throw RPCError.listenerFailed(error)
    }

    listenFD = fd
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: connectionQueue)
    source.setEventHandler { [weak self] in self?.acceptOne(from: fd) }
    source.setCancelHandler { Darwin.close(fd) }
    source.resume()
    acceptSource = source
    Reticulum.log("RPC server started on port \(port)", level: .info)
  }

  /// Stops listening and releases the socket.
  public func stop() {
    acceptSource?.cancel()
    acceptSource = nil
    listenFD = -1
  }

  // MARK: - Connection lifecycle

  private func acceptOne(from listener: Int32) {
    var peer = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let fd = withUnsafeMutablePointer(to: &peer) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.accept(listener, $0, &length) }
    }
    guard fd >= 0 else { return }
    var one: Int32 = 1
    Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    // `TCP_NODELAY`, the shared-instance option set: without it Nagle holds small control
    // frames behind the delayed-ACK timer.
    RNSSocketOptions.applyLocalOptions(toFileDescriptor: fd)
    var timeout = timeval(tv_sec: Self.ioTimeoutSeconds, tv_usec: 0)
    let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
    Darwin.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize)
    Darwin.setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize)

    let host = String(cString: inet_ntoa(peer.sin_addr))
    let endpoint = "\(host):\(UInt16(bigEndian: peer.sin_port))"
    connectionQueue.async { [weak self] in
      defer { Darwin.close(fd) }
      self?.serve(RPCSocket(fd: fd, endpoint: endpoint))
    }
  }

  /// One connection: mutual authentication, then one call and its response.
  private func serve(_ conn: RPCSocket) {
    guard authenticate(conn) else { return }
    guard let payload = conn.receiveFrame(limit: 1_048_576) else { return }
    let response = queue.sync { respond(to: payload) }
    _ = conn.sendFrame(response)
  }

  // MARK: - Mutual authentication

  /// Delivers this server's challenge, then answers the client's.
  ///
  /// Python's `connection.Client` runs `answer_challenge` (the client proves itself to the
  /// server) then `deliver_challenge` (the client verifies the server). The server must
  /// answer that second challenge or every RPC call fails with `AuthenticationError` before
  /// it starts.
  private func authenticate(_ conn: RPCSocket) -> Bool {
    // Modern (CPython ≥ 3.12) challenge: "{sha256}" + 40 random bytes. Legacy
    // clients (≤ 3.11) answer this with a bare HMAC-MD5 over the whole message,
    // which `verifyChallenge` also accepts—so one challenge serves both.
    let message = MultiprocessingAuth.makeChallengeMessage(digest: .sha256)
    guard conn.sendFrame(RPCServer.challengePrefix + message) else {
      Reticulum.log("RPC challenge send failed: \(Self.currentPOSIXError())", level: .error)
      return false
    }
    guard let digest = conn.receiveFrame(limit: 65536) else { return false }
    guard
      MultiprocessingAuth.verifyChallenge(authkey: authkey, message: message, response: digest)
    else {
      _ = conn.sendFrame(RPCServer.failureMessage)
      Reticulum.log("RPC auth failed from \(conn.endpoint)", level: .warning)
      return false
    }
    guard conn.sendFrame(RPCServer.welcomeMessage) else { return false }
    Reticulum.log("RPC client auth OK from \(conn.endpoint)", level: .debug)

    // The client's challenge is 20 raw bytes on CPython ≤ 3.11 and
    // "{sha256}" + 40 bytes on ≥ 3.12; accept either, and let
    // `createResponse` pick the matching digest and reply framing.
    guard let challenge = conn.receiveFrame(limit: 65536) else { return false }
    let prefix = RPCServer.challengePrefix
    guard challenge.count > prefix.count, challenge.prefix(prefix.count) == prefix else {
      Reticulum.log("RPC: bad client challenge (\(challenge.count) bytes)", level: .warning)
      return false
    }
    let nonce = Data(challenge.dropFirst(prefix.count))
    guard let response = try? MultiprocessingAuth.createResponse(authkey: authkey, message: nonce)
    else {
      Reticulum.log("RPC: unsupported client challenge format", level: .warning)
      return false
    }
    guard conn.sendFrame(response) else {
      Reticulum.log("RPC: digest send failed: \(Self.currentPOSIXError())", level: .error)
      return false
    }
    guard let verdict = conn.receiveFrame(limit: 65536) else { return false }
    guard verdict == RPCServer.welcomeMessage else {
      Reticulum.log("RPC: server auth rejected by client", level: .warning)
      return false
    }
    Reticulum.log("RPC mutual auth OK from \(conn.endpoint)", level: .debug)
    return true
  }

  // MARK: - MsgPack dispatch
  //
  // Calls arrive as MsgPack-encoded dicts (RNS ≥ 1.3.0 uses umsgpack for all
  // RPC payloads).  Responses are also MsgPack-encoded.

  /// Exposed `internal` so unit tests can call it directly via `@testable import`.
  func respond(to payload: Data) -> Data {
    guard let call = try? MsgPack.decode(payload),
      case .map(let pairs) = call
    else {
      Reticulum.log(
        "RPC: failed to decode MsgPack payload (\(payload.count) bytes) \(payload.prefix(16).map { String(format: "%02x", $0) }.joined())",
        level: .warning)
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

    // Interface management—{"manage": "<action>", "name": <name>} (RNS 1.5.5,
    // `Reticulum.py:1394-1398`). The reply is the tri-state verbatim: `rnstatus` prints a
    // different message for each value.
    if let manageKey = kv["manage"], case .string(let action) = manageKey {
      guard let reticulum, case .string(let name)? = kv["name"] else { return msgpack(.nil) }
      switch action {
      case "attach_interface": return msgpack(triState(reticulum.attachInterface(named: name)))
      case "detach_interface": return msgpack(triState(reticulum.detachInterface(named: name)))
      case "reload_interface": return msgpack(triState(reticulum.reloadInterface(named: name)))
      default: return msgpack(.nil)
      }
    }

    // Drop calls—{"drop": "<target>", ...}
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
      // every success read as "not blackholed"—in both directions.
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
        // Python: Reticulum.py:1230 returns the tri-state verbatim—see the
        // unblackhole_identity note earlier.
        return msgpack(triState(t.blackholeIdentity(hash, until: until, reason: reason)))
      }
      return msgpack(.nil)
    }

    Reticulum.log(
      "RPC: unrecognised call (\(payload.count) bytes) \(payload.prefix(32).map { String(format: "%02x", $0) }.joined())",
      level: .warning)
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

    case "active_link_count":
      guard let t = transport else { return msgpack(.int(0)) }
      return msgpack(.int(Int64(t.getActiveLinkCount())))

    case "next_hop":
      if let t = transport, let hash = binValue(kv["destination_hash"]),
        let hop = t.nextHop(to: hash)
      {
        return msgpack(.bytes(hop))
      }
      return msgpack(.nil)

    case "next_hop_if_name":
      // Python: `str(RNS.Transport.next_hop_interface(destination))`—the
      // interface's `__str__` (Swift: `displayName`, NOT `Interface.name`), and the
      // literal string "None" when there is no interface. A Python `rnprobe` tests
      // the response against the *string* "None", so answering msgpack nil made it
      // print " on None".
      if let t = transport, let hash = binValue(kv["destination_hash"]),
        let iface = t.nextHopInterface(for: hash)
      {
        return msgpack(.string(iface.displayName))
      }
      return msgpack(.string("None"))

    case "first_hop_timeout":
      if let t = transport, let hash = binValue(kv["destination_hash"]) {
        return msgpack(.double(t.firstHopTimeout(for: hash)))
      }
      return msgpack(.double(Transport.pathRequestTimeout))

    case "lowest_interface_bitrate":
      // Python returns `Transport.lowest_interface_bitrate` verbatim, which is `None`
      // until the first successful computation.
      guard let t = transport, let bitrate = t.lowestInterfaceBitrate else { return msgpack(.nil) }
      return msgpack(.int(Int64(bitrate)))

    case "medium_path_timeout":
      guard let t = transport else { return msgpack(.double(0)) }
      return msgpack(.double(t.mediumPathTimeout()))

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
        (
          .bytes(hash),
          .map([
            (.string("source"), entry.source.map { .bytes($0) } ?? .nil),
            (.string("until"), entry.until.map { .double($0) } ?? .nil),
            (.string("reason"), entry.reason.map { .string($0) } ?? .nil),
          ])
        )
      }
      return msgpack(.map(pairs))

    case "is_blackholed":
      if let t = transport, let hash = binValue(kv["identity_hash"]) {
        return msgpack(.bool(t.isBlackholed(hash)))
      }
      return msgpack(.bool(false))

    case "packet_rssi":
      if let t = transport, let hash = binValue(kv["packet_hash"]),
        let rssi = t.getPacketRssi(packetHash: hash)
      {
        // Python's RSSI is an integer (`byte - RSSI_OFFSET`, RNodeInterface.py:878)
        // and rnprobe renders it with `str()`, so a float here would print
        // "[RSSI -73.0 dBm]" where Python prints "[RSSI -73 dBm]". SNR and quality
        // below stay floats, matching RNodeInterface.py:880 and :890.
        return msgpack(.int(Int64(rssi.rounded())))
      }
      return msgpack(.nil)

    case "profiling_results":
      // Python: `Reticulum.get_profiling_results()` forwards this verb to the shared
      // instance (Reticulum.py:1862), which answers `RNS.Profiler.results()` or None.
      // This port instruments nothing with `@RNS.Profiler.profile`, so there is
      // never a result to return—the same answer an uninstrumented Python daemon
      // gives, and `rnstatus -z` prints nothing for either. Handled explicitly rather
      // than left to the unknown-path default so the answer is a decision, not a
      // by-product of the fallback.
      return msgpack(.nil)

    case "packet_snr":
      if let t = transport, let hash = binValue(kv["packet_hash"]),
        let snr = t.getPacketSnr(packetHash: hash)
      {
        return msgpack(.double(Double(snr)))
      }
      return msgpack(.nil)

    case "packet_q":
      if let t = transport, let hash = binValue(kv["packet_hash"]),
        let q = t.getPacketQ(packetHash: hash)
      {
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
        (.string("hash"), .bytes(entry.destinationHash)),
        (.string("timestamp"), .double(entry.lastHeard.timeIntervalSince1970)),
        (.string("via"), .bytes(entry.via)),
        (.string("hops"), .int(Int64(entry.hops))),
        (.string("expires"), .double(entry.expires.timeIntervalSince1970)),
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
        (.string("hash"), .bytes(entry.destinationHash)),
        (.string("last"), .double(entry.last)),
        (.string("rate_violations"), .int(Int64(entry.rateViolations))),
        (.string("blocked_until"), .double(entry.blockedUntil)),
        (.string("timestamps"), .array(entry.timestamps.map { .double($0) })),
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

  // MARK: - Errors

  private static func currentPOSIXError() -> Error {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  /// A failure raised while starting or serving the control socket.
  public enum RPCError: Error, CustomStringConvertible {
    case invalidPort
    case invalidProtocol
    /// The control socket couldn't be bound or listened on. Carries the `POSIXError`.
    case listenerFailed(Error?)

    /// A socket failure in the form Python prints an `OSError`: `[Errno 48] Address already in
    /// use`.
    public var description: String {
      switch self {
      case .invalidPort: return "invalid port"
      case .invalidProtocol: return "invalid protocol"
      case .listenerFailed(.some(let error as POSIXError)):
        return "[Errno \(error.code.rawValue)] \(String(cString: strerror(error.code.rawValue)))"
      case .listenerFailed(.some(let error)): return "\(error)"
      case .listenerFailed(.none): return "the control socket could not listen"
      }
    }
  }
}

/// One accepted control connection: blocking frame I/O on its descriptor.
///
/// A frame is a 4-byte big-endian signed length and the payload, as
/// `multiprocessing.connection`'s `send_bytes` and `recv_bytes` write and read it.
private struct RPCSocket {
  let fd: Int32
  /// `host:port` of the client, for log lines.
  let endpoint: String

  func sendFrame(_ payload: Data) -> Bool {
    var length = Int32(payload.count).bigEndian
    return write(Data(bytes: &length, count: 4) + payload)
  }

  /// The next frame's payload, or `nil` on end of stream, an error, a timeout, or a length
  /// outside `1..<limit`.
  func receiveFrame(limit: Int) -> Data? {
    guard let header = read(exactly: 4) else { return nil }
    let length = Int(Int32(bitPattern: header.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }))
    guard length > 0, length < limit else { return nil }
    return read(exactly: length)
  }

  private func write(_ data: Data) -> Bool {
    data.withUnsafeBytes { bytes in
      guard let base = bytes.baseAddress else { return true }
      var offset = 0
      while offset < bytes.count {
        let written = Darwin.write(fd, base + offset, bytes.count - offset)
        if written < 0 && errno == EINTR { continue }
        guard written > 0 else { return false }
        offset += written
      }
      return true
    }
  }

  private func read(exactly count: Int) -> Data? {
    var buffer = [UInt8](repeating: 0, count: count)
    var offset = 0
    while offset < count {
      let received = buffer.withUnsafeMutableBytes { bytes -> Int in
        guard let base = bytes.baseAddress else { return 0 }
        return Darwin.read(fd, base + offset, count - offset)
      }
      if received < 0 && errno == EINTR { continue }
      guard received > 0 else { return nil }
      offset += received
    }
    return Data(buffer)
  }
}
