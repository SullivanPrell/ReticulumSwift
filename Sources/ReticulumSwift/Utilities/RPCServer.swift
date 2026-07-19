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
    private let queue = DispatchQueue(label: "ReticulumSwift.RPCServer", attributes: .concurrent)

    /// Live transport reference — set by `Reticulum.startRPC` after creation.
    /// Weak to avoid a retain cycle (Transport → Reticulum → RPCServer → Transport).
    public weak var transport: Transport?

    private static let challengePrefix = "#CHALLENGE#".data(using: .utf8)!
    private static let welcomeMessage  = "#WELCOME#".data(using: .utf8)!
    private static let failureMessage  = "#FAILURE#".data(using: .utf8)!
    private static let messageLength   = 20

    public init(port: UInt16, authkey: Data) {
        self.port = port
        self.authkey = authkey
    }

    public func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw RPCError.invalidPort
        }
        let listener = try NWListener(using: .tcp, on: nwPort)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.handleConnection(conn) }
        listener.start(queue: queue)
        Reticulum.log("RPC server started on port \(port)", level: .info)
    }

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
        var message = Data(count: RPCServer.messageLength)
        _ = message.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, RPCServer.messageLength, $0.baseAddress!)
        }
        let challenge = RPCServer.challengePrefix + message

        sendBytes(challenge, over: conn) { [weak self] error in
            if let error {
                Reticulum.log("RPC challenge send failed: \(error)", level: .error)
                conn.cancel(); return
            }
            self?.receiveBytes(from: conn) { digest, err in
                guard let digest, err == nil else { conn.cancel(); return }
                let expected = self?.hmacMD5(key: self!.authkey, data: message)
                if digest == expected {
                    self?.sendBytes(RPCServer.welcomeMessage, over: conn) { _ in
                        Reticulum.log("RPC client auth OK from \(conn.endpoint)", level: .debug)
                        self?.answerChallenge(conn)
                    }
                } else {
                    self?.sendBytes(RPCServer.failureMessage, over: conn) { _ in
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
            guard challengeMsg.count == prefix.count + RPCServer.messageLength,
                  challengeMsg.prefix(prefix.count) == prefix else {
                Reticulum.log("RPC: bad client challenge (\(challengeMsg.count) bytes)", level: .warning)
                conn.cancel(); return
            }
            let nonce = Data(challengeMsg.dropFirst(prefix.count))
            let digest = self.hmacMD5(key: self.authkey, data: nonce)
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
            if let t = transport, let hash = binValue(ubhKey) {
                t.unblackholeIdentity(hash)
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
                t.blackholeIdentity(hash, until: until, reason: reason)
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
            guard let t = transport else { return msgpack(emptyInterfaceStats) }
            return msgpack(buildInterfaceStats(t))

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
            if let t = transport, let hash = binValue(kv["destination_hash"]),
               let ifName = t.nextHopInterfaceName(for: hash) {
                return msgpack(.string(ifName))
            }
            return msgpack(.nil)

        case "first_hop_timeout":
            if let t = transport, let hash = binValue(kv["destination_hash"]) {
                return msgpack(.double(t.firstHopTimeout(for: hash)))
            }
            return msgpack(.double(Transport.pathRequestTimeout))

        case "blackholed_identities":
            guard let t = transport else { return msgpack(.map([])) }
            t.blackholeLock.lock()
            let keys = Array(t.blackholedIdentities.keys)
            t.blackholeLock.unlock()
            let pairs: [(MsgPack.Value, MsgPack.Value)] = keys.map {
                (.bytes($0), .bool(true))
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
                return msgpack(.double(Double(rssi)))
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
            if let t = transport, let hash = binValue(kv["destination_hash"]) {
                t.expirePath(for: hash)
            }
            return msgpack(.nil)

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

    // MARK: - interface_stats builder

    private var emptyInterfaceStats: MsgPack.Value {
        .map([
            (.string("interfaces"), .array([])),
            (.string("rxb"),        .int(0)),
            (.string("txb"),        .int(0)),
            (.string("rxs"),        .double(0)),
            (.string("txs"),        .double(0)),
            (.string("rss"),        .nil),
        ])
    }

    private func buildInterfaceStats(_ t: Transport) -> MsgPack.Value {
        let now = Date().timeIntervalSince1970

        let interfaceValues: [MsgPack.Value] = t.interfaces.map { iface in
            var pairs: [(MsgPack.Value, MsgPack.Value)] = []

            func kv(_ k: String, _ v: MsgPack.Value) { pairs.append((.string(k), v)) }

            kv("name",       .string(iface.displayName))
            kv("short_name", .string(iface.name))
            kv("hash",       .bytes(Hashes.fullHash(Data(iface.displayName.utf8))))
            kv("type",       .string(String(describing: type(of: iface))))
            kv("rxb",        .int(Int64(iface.rxBytes)))
            kv("txb",        .int(Int64(iface.txBytes)))
            kv("status",     .bool(iface.isOnline))
            kv("mode",       .int(Int64(iface.mode.rawValue)))

            kv("incoming_announce_frequency",  .double(t.incomingAnnounceFrequency(for: iface)))
            kv("outgoing_announce_frequency",  .double(t.outgoingAnnounceFrequency(for: iface)))
            kv("incoming_pr_frequency",        .double(t.incomingPathRequestFrequency(for: iface)))
            kv("outgoing_pr_frequency",        .double(t.outgoingPathRequestFrequency(for: iface)))

            if let target = iface.announceRateTarget {
                kv("announce_rate_target", .double(target))
            } else {
                kv("announce_rate_target", .nil)
            }
            kv("announce_rate_penalty", .double(iface.announceRatePenalty))
            kv("announce_rate_grace",   .int(Int64(iface.announceRateGrace)))

            let ingress = t.ingressState(for: iface)
            kv("held_announces",     .int(Int64(t.heldAnnounceCount(for: iface))))
            kv("burst_active",       .bool(ingress?.burstActive    ?? false))
            kv("burst_activated",    .double(ingress?.burstActivated ?? 0))
            kv("pr_burst_active",    .bool(ingress?.prBurstActive    ?? false))
            kv("pr_burst_activated", .double(ingress?.prBurstActivated ?? 0))

            kv("rxs",     .double(t.currentRxSpeed(for: iface)))
            kv("txs",     .double(t.currentTxSpeed(for: iface)))
            kv("bitrate", .int(Int64(iface.bitrate)))

            if let qCount = t.announceQueueCount(for: iface) {
                kv("announce_queue", .int(Int64(qCount)))
            } else {
                kv("announce_queue", .nil)
            }

            // IFAC fields (present only when IFAC is configured)
            if iface.ifacIdentity != nil {
                kv("ifac_size",      .int(Int64(iface.ifacSize)))
                kv("ifac_signature", iface.ifacKey.map { .bytes($0) } ?? .nil)
            } else {
                kv("ifac_size",      .nil)
                kv("ifac_signature", .nil)
            }
            // ifac_netname is not stored in the Swift interface protocol; always nil
            kv("ifac_netname", .nil)
            kv("autoconnect_source", .nil)

            // --- Interface-type-specific fields (Python uses hasattr) ---

            // TCPServerInterface / PosixTCPServer: connected client count
            if let srv = iface as? TCPServerInterface {
                kv("clients", .int(Int64(srv.clientCount)))
            } else if let srv = iface as? PosixTCPServer {
                kv("clients", .int(Int64(srv.clientCount)))
            } else if let i2p = iface as? I2PInterface {
                kv("clients", .int(Int64(i2p.clients)))
            } else {
                kv("clients", .nil)
            }

            // RNodeInterface: airtime, channel load, battery, noise, interference
            if let rnode = iface as? RNodeInterface {
                kv("airtime_short",    .double(rnode.rAirtimeShort))
                kv("airtime_long",     .double(rnode.rAirtimeLong))
                kv("channel_load_short", .double(rnode.rChannelLoadShort))
                kv("channel_load_long",  .double(rnode.rChannelLoadLong))
                kv("noise_floor",      rnode.rNoiseFloor.map { .int(Int64($0)) } ?? .nil)
                kv("interference",     rnode.rInterference.map { .int(Int64($0)) } ?? .nil)
                let hasValidBattery = rnode.getBatteryState() != RNodeInterface.batteryStateUnknown
                if hasValidBattery {
                    kv("battery_state",   .string(rnode.getBatteryStateString()))
                    kv("battery_percent", .int(Int64(rnode.getBatteryPercent())))
                }
            }

            // WeaveInterfacePeer: switch_id, via_switch_id, endpoint_id
            if let weave = iface as? WeaveInterfacePeer {
                kv("switch_id",     weave.switchID.map    { .string($0.hexString) } ?? .nil)
                kv("via_switch_id", weave.viaSwitchID.map { .string($0.hexString) } ?? .nil)
                kv("endpoint_id",   weave.endpointID.map  { .string($0.hexString) } ?? .nil)
            }

            // I2PInterface: i2p_b32, tunnelstate, i2p_connectable
            if let i2p = iface as? I2PInterface {
                kv("i2p_connectable", .bool(i2p.connectable))
                kv("i2p_b32",     i2p.b32.map { .string($0 + ".b32.i2p") } ?? .nil)
                kv("tunnelstate", i2p.tunnelState.map { .string($0) } ?? .nil)
            }

            // RNodeSubInterface: parent_interface_name/hash (not yet wired — RNodeSubInterface
            // has no back-reference to the parent RNodeMultiInterface)
            // These fields would only appear in rnstatus if we add a parentMultiInterface
            // property to RNodeSubInterface. For now, they're omitted (rnstatus handles absence).

            return .map(pairs)
        }

        let tStats = t.getTransportStats()
        var topPairs: [(MsgPack.Value, MsgPack.Value)] = [
            (.string("interfaces"), .array(interfaceValues)),
            (.string("rxb"),        .int(Int64(tStats.trafficRxBytes))),
            (.string("txb"),        .int(Int64(tStats.trafficTxBytes))),
            (.string("rxs"),        .double(tStats.speedRx)),
            (.string("txs"),        .double(tStats.speedTx)),
            (.string("rss"),        .nil),
        ]

        if t.transportEnabled, let tid = t.transportIdentity {
            topPairs.append((.string("transport_id"), .bytes(tid.hash)))
            if let netID = t.networkIdentity {
                topPairs.append((.string("network_id"), .bytes(netID.hash)))
            } else {
                topPairs.append((.string("network_id"), .nil))
            }
            let uptime = t.startTime > 0 ? now - t.startTime : 0
            topPairs.append((.string("transport_uptime"), .double(uptime)))
            if let probe = t.probeDestination {
                topPairs.append((.string("probe_responder"), .bytes(probe.hash)))
            } else {
                topPairs.append((.string("probe_responder"), .nil))
            }
        }

        return .map(topPairs)
    }

    // MARK: - path_table builder

    private func buildPathTable(_ t: Transport, maxHops: UInt8?) -> MsgPack.Value {
        let entries = t.getPathTable(maxHops: maxHops)
        let values: [MsgPack.Value] = entries.map { entry in
            var pairs: [(MsgPack.Value, MsgPack.Value)] = [
                (.string("hash"),      .bytes(entry.destinationHash)),
                (.string("timestamp"), .double(entry.lastHeard.timeIntervalSince1970)),
                (.string("hops"),      .int(Int64(entry.hops))),
                (.string("expires"),   .double(entry.expires.timeIntervalSince1970)),
                (.string("interface"), .string(entry.interfaceName)),
            ]
            if let via = entry.via {
                pairs.append((.string("via"), .bytes(via)))
            } else {
                pairs.append((.string("via"), .nil))
            }
            return .map(pairs)
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

    private func hmacMD5(key: Data, data: Data) -> Data {
        let key = SymmetricKey(data: key)
        return Data(HMAC<Insecure.MD5>.authenticationCode(for: data, using: key))
    }

    public enum RPCError: Error {
        case invalidPort
        case invalidProtocol
    }
}

private extension NWConnection {
    func receive(exactly count: Int, completion: @escaping (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void) {
        self.receive(minimumIncompleteLength: count, maximumLength: count, completion: completion)
    }
}
