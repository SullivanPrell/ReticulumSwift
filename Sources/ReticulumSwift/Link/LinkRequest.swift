import Foundation

/// Request/response framing over a Link, matching Python's REQUEST
/// (0x09) / RESPONSE (0x0A) contexts.
///
/// Wire format (both directions are msgpack arrays):
///   request  = [time, path_hash, data]
///   response = [request_id, response_data]
/// where `path_hash = truncatedHash(path.utf8)` (16 bytes) and
/// `request_id = truncatedHash(hashable_part_of_wire_packet)` (16 bytes).
///
/// The request_id is derived from the wire packet's hashable bytes
/// (header nibble + dest_hash + context + ciphertext), **not** from the
/// plaintext body. This matches Python's `packet.getTruncatedHash()` which
/// hashes the same fields so that initiator and responder agree on the id
/// regardless of implementation language.
///
/// For payloads that exceed the link MDU, requests and responses are
/// sent as Resources with `isRequest`/`isResponse` flags set in the
/// advertisement. In the Resource path Python uses
/// `truncated_hash(packed_request)` (plaintext hash), so Swift uses the same
/// for large payloads.
public final class RequestReceipt {
    /// Mirrors Python's RequestReceipt status constants.
    public enum Status: Equatable {
        case sent                       // request packet/resource sent
        case delivered                  // request delivered, awaiting response
        case receiving(Double)          // response resource in progress (0–1)
        case ready(Data)                // response fully received
        case failed(reason: String)     // failed or timed out

        public static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.sent, .sent): return true
            case (.delivered, .delivered): return true
            case (.receiving(let a), .receiving(let b)): return a == b
            case (.ready(let a), .ready(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    public let requestID: Data
    public let path: String
    public let sentAt: Date
    public let requestSize: Int

    /// Guards every mutable field and callback below. `timeoutFired()` runs on a
    /// global queue while `deliverReady()`/`fail()`/`updateProgress()` run on the
    /// receive thread; without synchronization they race on `status` (allowing
    /// both onResponse and onFailed to fire) and a lockless read of the
    /// `Status`-with-`Data` enum can tear. Callbacks always fire OUTSIDE this
    /// lock, so it never nests with any other lock.
    private let stateLock = NSLock()

    private var _responseSize: Int?
    public var responseSize: Int? { stateLock.lock(); defer { stateLock.unlock() }; return _responseSize }
    private var _progress: Double = 0
    public var progress: Double { stateLock.lock(); defer { stateLock.unlock() }; return _progress }
    private var _concludedAt: Date?
    public var concludedAt: Date? { stateLock.lock(); defer { stateLock.unlock() }; return _concludedAt }
    private var _responseConcludedAt: Date?
    public var responseConcludedAt: Date? { stateLock.lock(); defer { stateLock.unlock() }; return _responseConcludedAt }
    private var _status: Status = .sent
    public var status: Status { stateLock.lock(); defer { stateLock.unlock() }; return _status }

    private var timeoutItem: DispatchWorkItem?

    private var _onResponse: ((Data, RequestReceipt) -> Void)?
    public var onResponse: ((Data, RequestReceipt) -> Void)? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _onResponse }
        set {
            // Replay-if-already-ready decided atomically with the assignment,
            // then fired outside the lock (closes the lost/double-callback window).
            stateLock.lock()
            _onResponse = newValue
            var replay: Data? = nil
            if case .ready(let d) = _status { replay = d }
            stateLock.unlock()
            if let d = replay { newValue?(d, self) }
        }
    }
    private var _onFailed: ((String, RequestReceipt) -> Void)?
    public var onFailed: ((String, RequestReceipt) -> Void)? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _onFailed }
        set {
            stateLock.lock()
            _onFailed = newValue
            var replay: String? = nil
            if case .failed(let r) = _status { replay = r }
            stateLock.unlock()
            if let r = replay { newValue?(r, self) }
        }
    }
    private var _onProgress: ((Double, RequestReceipt) -> Void)?
    public var onProgress: ((Double, RequestReceipt) -> Void)? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _onProgress }
        set { stateLock.lock(); _onProgress = newValue; stateLock.unlock() }
    }

    public init(requestID: Data, path: String, requestSize: Int, timeout: TimeInterval? = nil) {
        self.requestID = requestID
        self.path = path
        self.sentAt = Date()
        self.requestSize = requestSize
        if let t = timeout {
            let item = DispatchWorkItem { [weak self] in self?.timeoutFired() }
            self.timeoutItem = item
            DispatchQueue.global().asyncAfter(deadline: .now() + t, execute: item)
        }
    }

    func markDelivered() {
        stateLock.lock(); defer { stateLock.unlock() }
        guard case .sent = _status else { return }
        _status = .delivered
    }

    func updateProgress(_ p: Double) {
        stateLock.lock()
        // Don't move backwards out of a terminal state.
        switch _status {
        case .ready, .failed: stateLock.unlock(); return
        default: break
        }
        _progress = p
        _status = .receiving(p)
        let cb = _onProgress
        stateLock.unlock()
        cb?(p, self)
    }

    func deliverReady(_ data: Data, size: Int? = nil) {
        stateLock.lock()
        // Only conclude once, from a non-terminal state.
        switch _status {
        case .ready, .failed: stateLock.unlock(); return
        default: break
        }
        timeoutItem?.cancel()
        timeoutItem = nil
        _responseSize = size
        _responseConcludedAt = Date()
        _concludedAt = Date()
        _progress = 1.0
        _status = .ready(data)
        let cb = _onResponse
        stateLock.unlock()
        cb?(data, self)
    }

    func fail(_ reason: String) {
        stateLock.lock()
        // Only conclude once, from a non-terminal state (matches Python's guard;
        // do not overwrite a delivered .ready result with a late timeout).
        switch _status {
        case .ready, .failed: stateLock.unlock(); return
        default: break
        }
        timeoutItem?.cancel()
        timeoutItem = nil
        _concludedAt = Date()
        _status = .failed(reason: reason)
        let cb = _onFailed
        stateLock.unlock()
        cb?(reason, self)
    }

    private func timeoutFired() {
        // fail() itself is guarded; calling it unconditionally is safe.
        fail("timeout")
    }

    /// True if the response has been fully received.
    public var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    /// True if the request failed or timed out.
    public var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    /// The response data if status is `.ready`, otherwise nil.
    public var response: Data? {
        if case .ready(let d) = status { return d }
        return nil
    }

    /// Elapsed seconds from `sentAt` to when the response was received.
    public var responseTime: TimeInterval? {
        guard let r = responseConcludedAt else { return nil }
        return r.timeIntervalSince(sentAt)
    }
}

extension Link {

    /// Send a request along `path`. Returns a receipt the caller can attach
    /// `onResponse`/`onFailed` to.
    ///
    /// For small payloads (≤ link MDU) the request is sent as a single
    /// DATA/REQUEST packet; larger payloads go via Resource (matching Python's
    /// Link.request behavior).
    ///
    /// **request_id derivation:**
    /// - Small packets: `truncated_hash(hashable_part_of_wire_packet)` —
    ///   mirrors Python's `request_id = packet.getTruncatedHash()`.
    /// - Large (Resource): `truncated_hash(packed_request)` —
    ///   mirrors Python's Resource path.
    ///
    /// - Parameter timeout: Optional timeout in seconds. When the deadline
    ///   elapses without a response the receipt transitions to `.failed`
    ///   and `onFailed` is called (matching Python's request timeout).
    @discardableResult
    public func request(
        path: String,
        data: Data? = nil,
        responseCallback: ((Data, RequestReceipt) -> Void)? = nil,
        failedCallback: ((String, RequestReceipt) -> Void)? = nil,
        progressCallback: ((Double, RequestReceipt) -> Void)? = nil,
        timeout: TimeInterval? = nil
    ) throws -> RequestReceipt {
        // Wrap raw bytes as msgpack .bytes in the outer array (backward compatible).
        let dataValue: MsgPack.Value = data.map { .bytes($0) } ?? .nil
        return try request(path: path, dataValue: dataValue,
                           responseCallback: responseCallback, failedCallback: failedCallback,
                           progressCallback: progressCallback, timeout: timeout)
    }

    /// Python-wire-compatible request: embeds `nativeValue` directly in the outer
    /// msgpack array, matching Python's `msgpack.packb([ts, pathHash, data])` format.
    /// Use this when talking to Python nodes (e.g., LXMF propagation).
    @discardableResult
    public func request(
        path: String,
        nativeValue: MsgPack.Value,
        responseCallback: ((Data, RequestReceipt) -> Void)? = nil,
        failedCallback: ((String, RequestReceipt) -> Void)? = nil,
        progressCallback: ((Double, RequestReceipt) -> Void)? = nil,
        timeout: TimeInterval? = nil
    ) throws -> RequestReceipt {
        return try request(path: path, dataValue: nativeValue,
                           responseCallback: responseCallback, failedCallback: failedCallback,
                           progressCallback: progressCallback, timeout: timeout)
    }

    @discardableResult
    private func request(
        path: String,
        dataValue: MsgPack.Value,
        responseCallback: ((Data, RequestReceipt) -> Void)?,
        failedCallback: ((String, RequestReceipt) -> Void)?,
        progressCallback: ((Double, RequestReceipt) -> Void)?,
        timeout: TimeInterval?
    ) throws -> RequestReceipt {
        guard status == .active else { throw LinkError.notActive }

        let pathHash = Hashes.truncatedHash(Data(path.utf8))
        let body = MsgPack.encode(.array([
            .double(Date().timeIntervalSince1970),
            .bytes(pathHash),
            dataValue
        ]))

        // Default timeout mirrors Python: rtt * TRAFFIC_TIMEOUT_FACTOR + RESPONSE_MAX_GRACE_TIME*1.125
        let effectiveTimeout: TimeInterval?
        if let t = timeout {
            effectiveTimeout = t
        } else if let rtt {
            effectiveTimeout = rtt * Link.trafficTimeoutFactor + Link.requestTimeoutGrace
        } else {
            effectiveTimeout = nil
        }

        if body.count <= Constants.linkMdu {
            // ---------------------------------------------------------------
            // Small-packet path
            // Build the wire Packet first to compute request_id from its
            // hashable bytes (mirrors Python's getTruncatedHash).
            // Receipt is stored BEFORE send() so a synchronous loopback
            // transport can deliver the response without missing the lookup.
            // ---------------------------------------------------------------
            let (requestPacket, requestID) = try buildRequestPacket(body)

            let receipt = RequestReceipt(
                requestID: requestID,
                path: path,
                requestSize: body.count,
                timeout: effectiveTimeout
            )
            if let cb = responseCallback  { receipt.onResponse = cb }
            if let cb = failedCallback    { receipt.onFailed = cb }
            if let cb = progressCallback  { receipt.onProgress = cb }

            // Store before sending — response may arrive synchronously.
            pendingRequests[requestID] = receipt

            try sendPrebuiltPacket(requestPacket)

            return receipt
        } else {
            // ---------------------------------------------------------------
            // Large-payload (Resource) path
            // Python uses truncated_hash(packed_request) here, so we match.
            // ---------------------------------------------------------------
            let requestID = Hashes.truncatedHash(body)

            let receipt = RequestReceipt(
                requestID: requestID,
                path: path,
                requestSize: body.count,
                timeout: effectiveTimeout
            )
            if let cb = responseCallback  { receipt.onResponse = cb }
            if let cb = failedCallback    { receipt.onFailed = cb }
            if let cb = progressCallback  { receipt.onProgress = cb }

            pendingRequests[requestID] = receipt

            let rt = ResourceTransfer(link: self)
            rt.onFailed = { [weak receipt] _, _ in
                receipt?.fail("resource request transfer failed")
            }
            try rt.send(payload: body, requestID: requestID, isRequest: true)

            return receipt
        }
    }

    // MARK: - Incoming request (responder side)

    /// Dispatch an incoming REQUEST packet to the registered handler.
    ///
    /// `requestID` must be the **wire-format** packet hash
    /// (`packet.truncatedPacketHash()`), which is what Link.receive()
    /// passes after extracting it from the raw Packet. This matches Python's
    /// `request_id = packet.getTruncatedHash()` so the response body we send
    /// back carries the id the initiator expects.
    func handleIncomingRequest(_ data: Data, requestID: Data) {
        guard case .array(let parts) = (try? MsgPack.decode(data)) ?? .nil,
              parts.count >= 3 else { return }
        let requestedAt: Double = {
            if case .double(let t) = parts[0] { return t }
            if case .uint(let n) = parts[0] { return Double(n) }
            if case .int(let n) = parts[0] { return Double(n) }
            return 0
        }()
        guard case .bytes(let pathHash) = parts[1] else { return }
        // Re-encode parts[2] so bytes-based handlers receive msgpack bytes regardless of
        // whether the sender embedded the value natively (Python) or as bytes (old Swift).
        // A .nil parts[2] yields nil payload (matches Python's data=None).
        let rawValue = parts[2]
        let payload: Data? = {
            switch parts[2] {
            case .nil:              return nil
            case .bytes(let b):     // old Swift: try decoding inner bytes first
                if let decoded = try? MsgPack.decode(Data(b)),
                   case .nil = decoded { return nil }
                return Data(b)
            default:                return MsgPack.encode(parts[2])
            }
        }()
        dispatchRequest(pathHash: pathHash, payload: payload, rawValue: rawValue,
                        requestID: requestID, requestedAt: requestedAt)
    }

    /// Dispatch to registered request handler (checking allow policy) and
    /// send response (small or Resource). Mirrors Python's
    /// `Link.handle_request()`.
    ///
    /// - Parameter rawValue: The raw `MsgPack.Value` from parts[2] of the incoming
    ///   request wire frame. Passed directly to native handlers; unused by bytes handlers.
    func dispatchRequest(pathHash: Data, payload: Data?, rawValue: MsgPack.Value = .nil,
                         requestID: Data, requestedAt: Double) {
        guard let entry = destination.requestHandlers[pathHash] else { return }

        // Check allow policy (mirrors Python ALLOW_NONE/ALL/LIST).
        switch entry.allow {
        case .none:
            return
        case .all:
            break
        case .list:
            guard let remoteHash = remoteIdentity?.hash,
                  entry.allowedHashes.contains(remoteHash) else { return }
        }

        if let native = entry.nativeHandler {
            // Native (Python-compatible) handler: response embedded directly in envelope.
            guard let responseValue = native(pathHash, rawValue, requestID, self, requestedAt) else { return }
            let responseBody = MsgPack.encode(.array([.bytes(requestID), responseValue]))
            if responseBody.count <= Constants.linkMdu {
                try? send(responseBody, context: .response)
            } else {
                let encoded = MsgPack.encode(responseValue)
                let rt = ResourceTransfer(link: self)
                try? rt.send(payload: encoded, requestID: requestID, isResponse: true,
                             autoCompress: entry.autoCompress)
            }
        } else {
            // Bytes handler: response wrapped as .bytes in the envelope.
            guard let response = entry.handler(pathHash, payload, requestID, self, requestedAt) else { return }
            let responseBody = MsgPack.encode(.array([.bytes(requestID), .bytes(response)]))
            if responseBody.count <= Constants.linkMdu {
                try? send(responseBody, context: .response)
            } else {
                let rt = ResourceTransfer(link: self)
                try? rt.send(payload: response, requestID: requestID, isResponse: true,
                             autoCompress: entry.autoCompress)
            }
        }
    }

    // MARK: - Incoming response (initiator side)

    func handleIncomingResponse(_ data: Data) {
        guard case .array(let parts) = (try? MsgPack.decode(data)) ?? .nil,
              parts.count >= 2,
              case .bytes(let requestID) = parts[0] else { return }
        guard let receipt = pendingRequests.removeValue(forKey: requestID) else { return }
        // Response data may be any msgpack value (Python sends native objects; old Swift sent bytes).
        // Re-encode as bytes so callbacks receive a consistent Data payload to decode.
        let responseData: Data
        switch parts[1] {
        case .bytes(let b): responseData = Data(b)  // already bytes (old Swift encoding)
        default:            responseData = MsgPack.encode(parts[1])  // native value (Python encoding)
        }
        receipt.deliverReady(responseData)
    }

    // MARK: - Legacy stub (kept for call-site compatibility)

    /// No-op. REQUEST and RESPONSE contexts are now dispatched directly in
    /// `Link.receive()` using `packet.truncatedPacketHash()` for the request_id,
    /// matching Python's `packet.getTruncatedHash()` wire-compat semantics.
    func bindRequestDispatchIfNeeded() { }
}
