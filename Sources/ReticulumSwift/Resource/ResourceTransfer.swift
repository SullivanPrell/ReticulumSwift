import Foundation

/// Windowed, receiver-driven Resource transfer protocol over a Link.
///
/// Wire-compatible with Python `RNS.Resource`:
/// - Sender: sends ADV, waits for RESOURCE_REQ, sends requested segments,
///   waits for RESOURCE_PRF proof.
/// - Receiver: receives ADV, sends RESOURCE_REQ for first window,
///   receives parts, requests more, assembles, sends proof.
/// - RESOURCE data parts are NOT link-encrypted (resource pre-encrypts).
/// - RESOURCE_PRF proof is a PROOF type packet, sent without link encryption.
/// - All other resource control packets (ADV, REQ, HMU, ICL, RCL) are
///   link-encrypted like normal DATA packets.
///
/// ## Thread safety
///
/// All mutable transfer state is guarded by a single non-recursive `stateLock`
/// (a strict LEAF in the Transport lock hierarchy). The watchdog fires on a
/// dedicated serial queue while the Link receive thread and app/API threads
/// also drive the transfer, so every field mutation happens under `stateLock`
/// using **snapshot-under-lock / act-outside**: the lock is taken only to read
/// or mutate fields, and is ALWAYS released before any `link.*` call, callback,
/// `Resource` construction, or watchdog start/stop (all of which are callouts
/// that could re-enter this object or acquire another lock). Terminal
/// transitions (`.complete`/`.failed`/`.rejected`) are one-shot check-and-set
/// under the lock via `beginTerminalLocked(_:)`, and the paired callback fires
/// exactly once, outside the lock. This mirrors the discipline already used by
/// `RequestReceipt` and never holds `stateLock` across a callout (the
/// callout-under-lock pattern that previously deadlocked `Channel`).
public final class ResourceTransfer {

    public enum Status: Equatable {
        case idle
        case advertised       // Sender: ADV sent, waiting for REQ
        case transferring     // Both sides: transfer in progress
        case awaitingProof    // Sender: all parts sent, waiting for proof
        case complete
        case failed(reason: String)
        case rejected

        var isTerminal: Bool {
            switch self {
            case .complete, .failed, .rejected: return true
            default: return false
            }
        }
    }

    public enum Error: Swift.Error {
        case linkNotActive
        case payloadEmpty
    }

    // MARK: - Protocol constants (mirrors Python Resource class)

    static let mapHashLength: Int = 4      // MAPHASH_LEN
    static let hashmapIsNotExhausted: UInt8 = 0x00
    static let hashmapIsExhausted: UInt8 = 0xFF
    static let windowInitial: Int = 4      // WINDOW
    static let windowMin: Int = 2          // WINDOW_MIN
    static let windowMax: Int = 10         // WINDOW_MAX_SLOW
    /// Fast-window cap. Used only to size the collision-guard search window and to
    /// rewind the sender's search height after a hashmap update.
    /// Mirrors Python `Resource.WINDOW_MAX = WINDOW_MAX_FAST = 75`.
    static let windowMaxFast: Int = 75
    /// Maximum efficient segment size (~1 MB). Mirrors Python Resource.MAX_EFFICIENT_SIZE.
    public static let maxEfficientSize: Int = 1 * 1024 * 1024 - 1

    /// Test-only override for the segment size threshold. When non-nil, this value
    /// is used instead of `maxEfficientSize` to enable small-payload multi-segment tests.
    /// Set to nil (default) in production code.
    var testSegmentSizeOverride: Int? = nil

    // MARK: - Public state

    public let link: Link

    /// Serializes ALL mutable transfer state. A strict LEAF lock: it is NEVER
    /// held across any `link.*` call, callback, `Resource` init, or watchdog
    /// start/stop. Non-recursive — internal code holding it must use the `_`-backed
    /// fields (`_status`/`_advertisement`/…) and must never call a self-locking
    /// method (`sendRequest`/`assemble`/`fail`/`cancel`/`sendSegment`) while held.
    private let stateLock = NSLock()

    private var _status: Status = .idle
    /// Current transfer status. Reads/writes are serialized by `stateLock`.
    /// Torn reads of this enum (its `.failed` case carries a `String`) could
    /// crash — not merely garble — so external access goes through the lock.
    public private(set) var status: Status {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _status }
        set { stateLock.lock(); _status = newValue; stateLock.unlock() }
    }

    private var _advertisement: ResourceAdvertisement?
    /// The resource advertisement (nil until sent/received). Lock-guarded: a torn
    /// read of this optional class reference would be an ARC use-after-free.
    public private(set) var advertisement: ResourceAdvertisement? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _advertisement }
        set { stateLock.lock(); _advertisement = newValue; stateLock.unlock() }
    }

    /// True when this transfer is the RECEIVER of an incoming resource (set once an
    /// advertisement is received). Senders leave this false. Mirrors the inverse of
    /// Python's `Resource.initiator`: on cancel a receiver emits RESOURCE_RCL while a
    /// sender emits RESOURCE_ICL.
    private var isReceiver: Bool = false

    /// Wall-clock time when data transfer began (first REQ sent/received).
    /// Used to compute `link.expectedRate` on completion. Mirrors Python `Resource.started_transferring`.
    private var startedTransferring: Date?

    private var _resourceHash: Data = Data()
    /// Full 32-byte SHA256 resource hash. Set after send() or receiveAdvertisement().
    /// Lock-guarded for safe concurrent reads from the public getter.
    public private(set) var resourceHash: Data {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _resourceHash }
        set { stateLock.lock(); _resourceHash = newValue; stateLock.unlock() }
    }

    public var onComplete: ((ResourceTransfer) -> Void)?
    public var onFailed: ((ResourceTransfer, Status) -> Void)?
    /// Receiver-side: fires with the reassembled plaintext once verified.
    public var onPayloadReceived: ((Data, ResourceTransfer) -> Void)?

    // MARK: - Accessor properties (mirrors Python Resource getter methods)

    /// Transfer progress as a value from 0.0 to 1.0.
    /// Mirrors Python's `Resource.get_progress()`.
    public var progress: Double {
        stateLock.lock(); defer { stateLock.unlock() }
        if case .complete = _status { return 1.0 }
        if totalParts == 0 { return 0.0 }
        return min(1.0, Double(receivedCount) / Double(totalParts))
    }

    /// The number of bytes needed to transfer the resource (encrypted).
    /// Mirrors Python's `Resource.get_transfer_size()`.
    public var transferSize: Int { Int(advertisement?.transferSize ?? 0) }

    /// The total data size of the resource (original uncompressed).
    /// Mirrors Python's `Resource.get_data_size()`.
    public var dataSize: Int { Int(advertisement?.dataSize ?? 0) }

    /// The number of parts the resource is transferred in.
    /// Mirrors Python's `Resource.get_parts()`.
    public var partCount: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return totalParts > 0 ? totalParts : encryptedSegments.count
    }

    /// The number of segments the resource is divided into.
    /// Mirrors Python's `Resource.get_segments()`.
    public var segmentCount: Int { Int(advertisement?.totalSegments ?? 1) }

    /// The resource hash (32-byte SHA-256).
    /// Mirrors Python's `Resource.get_hash()`.
    public var hash: Data { resourceHash }

    /// Whether the resource data is compressed.
    /// Mirrors Python's `Resource.is_compressed()`.
    public var isCompressed: Bool { advertisement?.compressed ?? false }

    /// Returns `true` if metadata was included with this resource.
    /// Mirrors Python `Resource.has_metadata()` (on ResourceAdvertisement).
    public var hasMetadata: Bool { advertisement?.hasMetadata ?? false }

    /// The link this resource is being transferred over.
    /// Mirrors Python `Resource.get_link()`.
    public var resourceLink: Link { link }

    /// Python-compatible getter methods (mirrors Python `Resource.get_progress()` etc.)
    public func getProgress() -> Double { progress }
    public func getTransferSize() -> Int { transferSize }
    public func getDataSize() -> Int { dataSize }
    public func getParts() -> Int { partCount }
    public func getSegments() -> Int { segmentCount }
    public func getHash() -> Data { hash }

    /// Called periodically with (progress, resource) as parts arrive.
    public var onProgress: ((Double, ResourceTransfer) -> Void)?

    /// Set the completion callback. Mirrors Python `Resource.set_callback(callback)`.
    public func setCallback(_ callback: @escaping (ResourceTransfer) -> Void) {
        onComplete = callback
    }

    /// Set the progress callback. Mirrors Python `Resource.progress_callback(callback)`.
    public func setProgressCallback(_ callback: @escaping (Double, ResourceTransfer) -> Void) {
        onProgress = callback
    }

    /// Internal hook used by Link to intercept isRequest/isResponse assemblies
    /// before calling the public callbacks. Set by Link.receive().
    var onAssembledInternal: ((Data, ResourceTransfer) -> Void)?

    private var _receivedMetadata: Data?
    /// Set on the receiver side after successful assembly when the sender included metadata.
    /// The bytes are the raw pre-packed metadata (without the 3-byte size prefix).
    /// Lock-guarded for safe concurrent reads.
    public private(set) var receivedMetadata: Data? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _receivedMetadata }
        set { stateLock.lock(); _receivedMetadata = newValue; stateLock.unlock() }
    }

    // MARK: - Multi-segment receiver state
    // Mirrors Python's segmented resource protocol (total_segments > 1).

    /// Accumulated payload bytes from completed prior segments (indices 1..N-1).
    private var segmentBuffer: [Data] = []
    /// Original hash (same across all segments of one multi-segment transfer).
    private(set) var originalHash: Data?
    /// Metadata extracted from the first segment (if any). Preserved across segment transitions.
    private var multiSegmentMetadata: Data?

    // MARK: - Sender state

    private var encryptedSegments: [Data] = []
    private var mapHashes: [Data] = []
    private var randomHash: Data = Data()
    private var expectedProof: Data = Data()
    /// Set of map-hashes for segments that have been sent at least once.
    private var sentMapHashes: Set<Data> = []
    /// Lower bound of the sender's part-search window, advanced as the receiver pulls
    /// later hashmap segments. Mirrors Python `Resource.receiver_min_consecutive_height`.
    private var receiverMinConsecutiveHeight: Int = 0

    // Multi-segment sender state.
    private var pendingSegments: [Data] = []    // remaining segment payloads (indices 2..N)
    private var segmentIndex: Int = 1
    private var totalSegments: Int = 1
    private var overallOriginalHash: Data = Data()
    private var segmentRequestID: Data?
    private var segmentIsRequest: Bool = false
    private var segmentIsResponse: Bool = false
    private var segmentMetadata: Data?
    private var segmentAutoCompress: Bool = true

    // MARK: - Receiver state

    private var parts: [Data?] = []
    private var hashmap: [Data?] = []
    private var consecutiveCompletedHeight: Int = -1
    private var window: Int = windowInitial
    private var outstandingParts: Int = 0
    private var waitingForHMU: Bool = false
    private var receivedCount: Int = 0
    private var totalParts: Int = 0

    // MARK: - Watchdog

    /// Maximum retries before failing (sender: awaiting proof; receiver: awaiting parts).
    public var maxRetries: Int = 16
    /// Maximum ADV retransmissions (sender: awaiting first REQ).
    public var maxAdvRetries: Int = 4
    /// Timeout per retry round (seconds). Not RTT-adapted — matches Python SENDER_GRACE_TIME.
    public var retryTimeout: TimeInterval = 30.0

    private var retriesLeft: Int = 16
    private var lastActivity: Date = Date()
    private var watchdogTimer: DispatchSourceTimer?
    private static let watchdogQueue = DispatchQueue(label: "ResourceTransfer.watchdog")

    // MARK: - Init

    public init(link: Link) {
        self.link = link
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        stopWatchdog()
        let t = DispatchSource.makeTimerSource(queue: ResourceTransfer.watchdogQueue)
        t.schedule(deadline: .now() + retryTimeout, repeating: retryTimeout)
        t.setEventHandler { [weak self] in self?.watchdogTick() }
        stateLock.lock(); watchdogTimer = t; stateLock.unlock()
        t.resume()
    }

    private func stopWatchdog() {
        stateLock.lock(); let t = watchdogTimer; watchdogTimer = nil; stateLock.unlock()
        t?.cancel()
    }

    private func watchdogTick() {
        stateLock.lock()
        if _status.isTerminal { stateLock.unlock(); stopWatchdog(); return }
        let sinceActivity = Date().timeIntervalSince(lastActivity)
        guard sinceActivity >= retryTimeout else { stateLock.unlock(); return }

        if retriesLeft > 0 {
            retriesLeft -= 1
            lastActivity = Date()
            let snapStatus = _status
            let adv = _advertisement
            stateLock.unlock()

            // ACT OUTSIDE LOCK — every branch below calls into Link.
            switch snapStatus {
            case .advertised:
                // No REQ received — retransmit ADV.
                if let adv { try? link.send(adv.pack(), context: .resourceAdvertisement) }
            case .transferring:
                // Receiver: outstanding parts not received — resend REQ.
                sendRequest()
            case .awaitingProof:
                // All parts sent but no proof — nothing to do (proof may arrive late).
                break
            default:
                break
            }
        } else {
            stateLock.unlock()
            fail("watchdog timeout")
        }
    }

    // MARK: - Sender

    /// Prepare and advertise a resource. The sender registers with the link,
    /// which will call `handleRequest(_:)` when the receiver requests parts.
    /// Set `requestID` and `isRequest`/`isResponse` for request/response transfers.
    public func send(
        payload: Data,
        metadata: Data? = nil,
        segmentSize: Int = Constants.mdu,
        requestID: Data? = nil,
        isRequest: Bool = false,
        isResponse: Bool = false,
        autoCompress: Bool = true
    ) throws {
        guard link.status == .active else { throw Error.linkNotActive }
        guard !payload.isEmpty else { throw Error.payloadEmpty }

        // Split into segments of MAX_EFFICIENT_SIZE when payload is large.
        // Mirrors Python Resource.__init__ splitting logic.
        let maxSeg = testSegmentSizeOverride ?? ResourceTransfer.maxEfficientSize
        if payload.count > maxSeg {
            var chunks: [Data] = []
            var offset = 0
            while offset < payload.count {
                let end = min(offset + maxSeg, payload.count)
                chunks.append(payload[offset ..< end])
                offset = end
            }
            stateLock.lock()
            pendingSegments = Array(chunks.dropFirst())
            segmentIndex = 1
            totalSegments = chunks.count
            segmentMetadata = metadata
            segmentRequestID = requestID
            segmentIsRequest = isRequest
            segmentIsResponse = isResponse
            segmentAutoCompress = autoCompress
            stateLock.unlock()

            // Compute original_hash from the first segment's resource hash
            // (will be set after resource init). Use first segment to start.
            try sendSegment(payload: chunks[0], metadata: metadata,
                            segmentSize: segmentSize, requestID: requestID,
                            isRequest: isRequest, isResponse: isResponse,
                            autoCompress: autoCompress)
            return
        }

        try sendSegment(payload: payload, metadata: metadata, segmentSize: segmentSize,
                        requestID: requestID, isRequest: isRequest, isResponse: isResponse,
                        autoCompress: autoCompress)
    }

    private func sendSegment(
        payload: Data, metadata: Data?, segmentSize: Int,
        requestID: Data?, isRequest: Bool, isResponse: Bool, autoCompress: Bool = true
    ) throws {
        // Resource construction is a callout (reads link state, performs crypto) —
        // build it OUTSIDE the lock.
        let resource = try Resource(link: link, payload: payload, metadata: metadata,
                                    segmentSize: segmentSize, autoCompress: autoCompress)

        stateLock.lock()
        encryptedSegments = resource.encryptedSegments
        mapHashes = resource.mapHashes
        randomHash = resource.randomHash
        _resourceHash = resource.resourceHash
        expectedProof = resource.expectedProof
        // For segment 1, set overallOriginalHash = first segment's resource hash.
        if segmentIndex == 1 { overallOriginalHash = resource.resourceHash }
        let segIdxSnapshot = segmentIndex
        let totalSegSnapshot = totalSegments
        let overallHashSnapshot = overallOriginalHash
        let reqIDSnapshot = requestID ?? segmentRequestID
        let isReqSnapshot = isRequest || segmentIsRequest
        let isRespSnapshot = isResponse || segmentIsResponse
        stateLock.unlock()

        let adv = ResourceAdvertisement(
            transferSize: UInt64(resource.transferSize),
            dataSize: UInt64(resource.dataSize),
            partCount: UInt64(resource.partCount),
            resourceHash: resource.resourceHash,
            randomHash: resource.randomHash,
            originalHash: overallHashSnapshot,
            segmentIndex: UInt64(segIdxSnapshot),
            totalSegments: UInt64(totalSegSnapshot),
            requestID: reqIDSnapshot,
            hashmap: resource.mapHashes.reduce(Data(), +),
            encrypted: true,
            compressed: resource.isCompressed,
            split: totalSegSnapshot > 1,
            isRequest: isReqSnapshot,
            isResponse: isRespSnapshot,
            hasMetadata: resource.hasMetadata
        )

        stateLock.lock()
        _advertisement = adv
        _status = .advertised
        retriesLeft = maxAdvRetries
        lastActivity = Date()
        stateLock.unlock()

        link.registerOutgoingResource(self)
        guard ensureLinkActive() else { return }
        try link.send(adv.pack(), context: .resourceAdvertisement)
        startWatchdog()
    }

    /// Called by Link when a RESOURCE_REQ arrives for our resource hash.
    internal func handleRequest(_ data: Data) {
        guard !data.isEmpty else { return }

        let wantsMoreHashmap = data[0] == ResourceTransfer.hashmapIsExhausted
        let pad = wantsMoreHashmap ? 1 + ResourceTransfer.mapHashLength : 1
        guard data.count > pad + Constants.hashLength else { return }

        let requestedHashesData = data[(pad + Constants.hashLength)...]
        var requestedHashes: Set<Data> = []
        var i = requestedHashesData.startIndex
        while i + ResourceTransfer.mapHashLength <= requestedHashesData.endIndex {
            requestedHashes.insert(Data(requestedHashesData[i ..< i + ResourceTransfer.mapHashLength]))
            i += ResourceTransfer.mapHashLength
        }

        stateLock.lock()
        guard _status == .advertised || _status == .transferring || _status == .awaitingProof else {
            stateLock.unlock(); return
        }
        if _status != .transferring {
            _status = .transferring
            if startedTransferring == nil { startedTransferring = Date() }
        }
        lastActivity = Date()
        retriesLeft = maxRetries

        // Send the requested parts, searching only within the collision-guard window
        // around the receiver's consecutive height. A windowed search ensures the
        // correct part is sent even when a 4-byte map-hash collides with a distant
        // part elsewhere in the resource. Mirrors Python `Resource.request`.
        //
        // Snapshot the exact byte payloads to send (NOT indices) under the lock so a
        // concurrent multi-segment advance can't swap `encryptedSegments` out from
        // under the send loop.
        var partsToSend: [Data] = []
        let sendStart = min(receiverMinConsecutiveHeight, mapHashes.count)
        let sendEnd = min(receiverMinConsecutiveHeight + ResourceAdvertisement.collisionGuardSize, mapHashes.count)
        for idx in sendStart ..< sendEnd {
            let mapHash = mapHashes[idx]
            if requestedHashes.contains(mapHash) {
                partsToSend.append(encryptedSegments[idx])
                sentMapHashes.insert(mapHash)
            }
        }

        // If the receiver exhausted its known hashmap, compute the next HMU segment
        // (or a cancellation) under the lock — but SEND it outside.
        var hmuPayload: Data? = nil
        var cancelReason: String? = nil
        if wantsMoreHashmap, data.count >= 1 + ResourceTransfer.mapHashLength {
            let lastMapHash = Data(data[1 ..< 1 + ResourceTransfer.mapHashLength])

            // Locate the part following lastMapHash within the collision-guard window.
            // After the loop `partIndex` is (index of lastMapHash) + 1 — the first part
            // of the next hashmap segment. Mirrors Python `Resource.request`.
            var partIndex = receiverMinConsecutiveHeight
            let pivotEnd = min(receiverMinConsecutiveHeight + ResourceAdvertisement.collisionGuardSize, mapHashes.count)
            for idx in receiverMinConsecutiveHeight ..< pivotEnd {
                partIndex += 1
                if mapHashes[idx] == lastMapHash { break }
            }
            receiverMinConsecutiveHeight = max(partIndex - 1 - ResourceTransfer.windowMaxFast, 0)

            let hml = ResourceAdvertisement.hashmapMaxLength
            if partIndex % hml != 0 {
                // Next segment is not aligned to a HASHMAP_MAX_LEN boundary — the
                // receiver's request is out of sequence. Abort, as Python does.
                cancelReason = "resource sequencing error"
            } else {
                let segment = partIndex / hml
                let hashmapStart = segment * hml
                let hashmapEnd = min((segment + 1) * hml, mapHashes.count)
                if hashmapStart >= hashmapEnd {
                    // Degenerate/empty HMU request — abort rather than silently skip.
                    // Mirrors Python `request()` (`if not hashmap: cancel()`).
                    cancelReason = "resource HMU error"
                } else {
                    let hmuHashmap = mapHashes[hashmapStart ..< hashmapEnd].reduce(Data(), +)
                    hmuPayload = _resourceHash + MsgPack.encode(.array([
                        .uint(UInt64(segment)),
                        .bytes(hmuHashmap)
                    ]))
                }
            }
        }
        stateLock.unlock()

        // ACT OUTSIDE LOCK — preserve the original send order: parts, then HMU
        // (or, on a sequencing error, cancel and return before advancing state).
        for part in partsToSend {
            try? link.sendResourcePart(part)
        }
        if let cancelReason {
            cancel(reason: cancelReason)
            return
        }
        if let hmuPayload {
            guard ensureLinkActive() else { return }
            try? link.send(hmuPayload, context: .resourceHashmapUpdate)
        }

        // If proof already arrived (loopback) leave the completed status alone.
        // Advance to awaitingProof once every segment has been sent at least once.
        stateLock.lock()
        if _status != .complete, _status != .rejected, sentMapHashes.count == mapHashes.count {
            _status = .awaitingProof
        }
        stateLock.unlock()
    }

    /// Called by Link when a RESOURCE_PRF proof arrives for our resource hash.
    internal func validateProof(_ proofData: Data) {
        // Proof wire format: hash (32 bytes) || sha256(transferData + hash) (32 bytes)
        guard proofData.count == Constants.hashLength * 2 else {
            fail("proof wrong length: \(proofData.count)")
            return
        }
        let receivedProof = proofData.suffix(Constants.hashLength)
        stateLock.lock(); let expected = expectedProof; stateLock.unlock()
        guard Data(receivedProof) == expected else {
            fail("proof mismatch")
            return
        }

        // Snapshot conclusion / segment-advance state under the lock; act outside.
        stateLock.lock()
        let started = startedTransferring
        let advDataSize = Int(_advertisement?.dataSize ?? 0)
        let hasMoreSegments = !pendingSegments.isEmpty
        var nextSegment: Data? = nil
        var nextReqID: Data? = nil
        var nextIsRequest = false
        var nextIsResponse = false
        var nextAutoCompress = true
        if hasMoreSegments {
            nextSegment = pendingSegments.removeFirst()
            segmentIndex += 1
            nextReqID = segmentRequestID
            nextIsRequest = segmentIsRequest
            nextIsResponse = segmentIsResponse
            nextAutoCompress = segmentAutoCompress
        }
        stateLock.unlock()

        // ACT OUTSIDE LOCK.
        stopWatchdog()
        link.unregisterOutgoingResource(self)

        // Update link expected rate (mirrors Python Link.resource_concluded).
        if let started {
            let duration = Date().timeIntervalSince(started)
            link.resourceConcluded(dataSize: advDataSize, duration: duration)
        }

        // Multi-segment: if more segments remain, advance and advertise next.
        if hasMoreSegments, let next = nextSegment {
            stateLock.lock(); _status = .idle; stateLock.unlock()
            do {
                try sendSegment(
                    payload: next,
                    metadata: nil,  // metadata only on first segment
                    segmentSize: Constants.mdu,
                    requestID: nextReqID,
                    isRequest: nextIsRequest,
                    isResponse: nextIsResponse,
                    autoCompress: nextAutoCompress
                )
            } catch {
                fail("multi-segment next: \(error)")
            }
            return
        }

        stateLock.lock(); _status = .complete; stateLock.unlock()
        onComplete?(self)
    }

    internal func reject() {
        stateLock.lock(); _status = .rejected; stateLock.unlock()
        stopWatchdog()
        link.unregisterOutgoingResource(self)
        onFailed?(self, .rejected)
    }

    // MARK: - Receiver

    /// Bind this transfer as a receiver. The link will call `receiveAdvertisement`
    /// when an ADV arrives and route RESOURCE parts here.
    public func bindAsReceiver() {
        link.registerIncomingResource(self)
    }

    /// Called by Link when a RESOURCE_ADV arrives (decrypted plaintext).
    internal func receiveAdvertisement(_ data: Data) {
        guard let adv = try? ResourceAdvertisement.unpack(data) else {
            fail("unparseable advertisement")
            return
        }
        // Bound the advertised part count before it sizes the `parts`/`hashmap`
        // arrays. `partCount` (the wire "n" field) is attacker-controlled; a
        // hostile advertisement could declare a near-UInt64 count and force an
        // astronomical allocation (OOM/trap DoS) even over an authenticated link.
        // The transfer size `t` is already capped at 3*maxEfficientSize by
        // ResourceAdvertisement.unpack, and every part carries at least one byte of
        // the transfer, so a legitimate `n` can never exceed `t`. (Python never
        // trusts `n` at all — it derives total_parts = ceil(size/sdu); this bound
        // is the wire-neutral equivalent that still accepts every valid transfer.)
        guard adv.partCount <= adv.transferSize else {
            fail("advertised part count exceeds transfer size")
            return
        }

        stateLock.lock()
        isReceiver = true
        _advertisement = adv
        _resourceHash = adv.resourceHash
        totalParts = Int(adv.partCount)

        // Build hashmap array from advertisement bytes.
        hashmap = []
        var offset = 0
        let hm = adv.hashmap
        while offset + ResourceTransfer.mapHashLength <= hm.count {
            hashmap.append(Data(hm[offset ..< offset + ResourceTransfer.mapHashLength]))
            offset += ResourceTransfer.mapHashLength
        }
        // Pad with nil for unknown entries (large resources with multi-segment hashmap).
        while hashmap.count < totalParts {
            hashmap.append(nil)
        }

        parts = [Data?](repeating: nil, count: totalParts)
        consecutiveCompletedHeight = -1
        receivedCount = 0
        window = ResourceTransfer.windowInitial
        outstandingParts = 0
        waitingForHMU = false
        _status = .transferring
        retriesLeft = maxRetries
        lastActivity = Date()
        if startedTransferring == nil { startedTransferring = Date() }
        stateLock.unlock()

        startWatchdog()
        sendRequest()
    }

    /// Called by Link for each inbound RESOURCE data part (raw pre-encrypted bytes).
    internal func receivePart(_ data: Data) {
        stateLock.lock()
        guard _status == .transferring else { stateLock.unlock(); return }
        lastActivity = Date()
        retriesLeft = maxRetries

        let partHash = Hashes.fullHash(data + randomHashForReceiverLocked()).prefix(ResourceTransfer.mapHashLength)
        let partHashData = Data(partHash)

        // Match the part against the window of known hashmap entries.
        let searchStart = max(0, consecutiveCompletedHeight + 1)
        let searchEnd = min(searchStart + window, totalParts)

        for i in searchStart ..< searchEnd {
            guard let mh = hashmap[i], mh == partHashData else { continue }
            if parts[i] == nil {
                parts[i] = data
                receivedCount += 1
                outstandingParts = max(0, outstandingParts - 1)

                // Advance consecutive completed pointer.
                if i == consecutiveCompletedHeight + 1 {
                    consecutiveCompletedHeight = i
                    var cp = consecutiveCompletedHeight + 1
                    while cp < parts.count, parts[cp] != nil {
                        consecutiveCompletedHeight = cp
                        cp += 1
                    }
                }
            }
            break
        }

        let doAssemble = (receivedCount == totalParts)
        var doSendRequest = false
        if !doAssemble, outstandingParts == 0 {
            if window < ResourceTransfer.windowMax { window += 1 }
            doSendRequest = true
        }
        stateLock.unlock()

        // ACT OUTSIDE LOCK (assemble/sendRequest do their own locking + callouts).
        if doAssemble {
            assemble()
        } else if doSendRequest {
            sendRequest()
        }
    }

    /// Called by Link when a RESOURCE_HMU arrives (decrypted plaintext starting with resourceHash).
    internal func handleHashmapUpdate(_ data: Data) {
        guard data.count > Constants.hashLength else { return }
        let payload = data.dropFirst(Constants.hashLength)
        guard case .array(let arr) = (try? MsgPack.decode(Data(payload))),
              arr.count >= 2,
              case .uint(let segIdx) = arr[0],
              case .bytes(let hmap) = arr[1] else { return }

        stateLock.lock()
        guard _status == .transferring else { stateLock.unlock(); return }
        // Only process a hashmap update we actually requested; unsolicited or
        // duplicate HMUs are ignored. Mirrors Python `hashmap_update_packet`
        // gating on `self.waiting_for_hmu` (commit 3a36c367).
        guard waitingForHMU else { stateLock.unlock(); return }

        // An HMU carrying fewer than one full map-hash is invalid — abort the
        // transfer. Mirrors Python `hashmap_update` (`if hashes < 1: cancel()`).
        guard hmap.count >= ResourceTransfer.mapHashLength else {
            stateLock.unlock()
            cancel(reason: "invalid HMU received")
            return
        }

        let segLen = ResourceAdvertisement.hashmapMaxLength
        var offset = 0
        // `segIdx` is an attacker-controlled msgpack uint. The original
        // `Int(segIdx) * segLen` traps twice: the UInt64→Int narrowing crashes for
        // values > Int.max, and the multiply can overflow Int. Compute the start
        // index with overflow-safe arithmetic; any value that doesn't fit or whose
        // product overflows is out of range and clamped past the end, so the loop's
        // existing `i < totalParts` guard makes it a no-op instead of crashing.
        // Wire-neutral: for a valid (small) segment index the result is identical.
        let start: Int
        if let s = Int(exactly: segIdx) {
            let (product, overflow) = s.multipliedReportingOverflow(by: segLen)
            start = overflow ? totalParts : product
        } else {
            start = totalParts
        }
        var i = start
        while offset + ResourceTransfer.mapHashLength <= hmap.count, i < totalParts {
            if hashmap[i] == nil {
                hashmap[i] = Data(hmap[offset ..< offset + ResourceTransfer.mapHashLength])
            }
            offset += ResourceTransfer.mapHashLength
            i += 1
        }

        waitingForHMU = false
        stateLock.unlock()
        sendRequest()
    }

    /// Cancel the resource transfer. Transitions to `.failed` and calls `onFailed`.
    /// Mirrors Python's `Resource.cancel()`.
    public func cancel() {
        cancel(reason: "cancelled by application")
    }

    internal func cancel(reason: String) {
        fail(reason)
    }

    // MARK: - Private receiver helpers

    /// Caller MUST hold `stateLock`.
    private func randomHashForReceiverLocked() -> Data {
        _advertisement?.randomHash ?? Data()
    }

    private func sendRequest() {
        stateLock.lock()
        guard !waitingForHMU else { stateLock.unlock(); return }
        outstandingParts = 0
        var requestedHashes = Data()
        var hashmapExhausted = false
        var lastKnownHash = Data()

        let searchStart = max(0, consecutiveCompletedHeight + 1)
        var i = searchStart
        var count = 0
        while i < totalParts, count < window {
            if parts[i] == nil {
                if let mh = hashmap[i] {
                    requestedHashes.append(contentsOf: mh)
                    outstandingParts += 1
                    count += 1
                } else {
                    // Hashmap entry unknown — request more hashmap.
                    hashmapExhausted = true
                    // Find the last known hash to send to sender.
                    for j in stride(from: i - 1, through: 0, by: -1) {
                        if let mh = hashmap[j] {
                            lastKnownHash = mh
                            break
                        }
                    }
                    break
                }
            }
            i += 1
        }

        var reqData = Data()
        if hashmapExhausted {
            reqData.append(ResourceTransfer.hashmapIsExhausted)
            reqData.append(contentsOf: lastKnownHash.prefix(ResourceTransfer.mapHashLength))
            waitingForHMU = true
        } else {
            reqData.append(ResourceTransfer.hashmapIsNotExhausted)
        }
        reqData.append(contentsOf: _resourceHash)
        reqData.append(contentsOf: requestedHashes)
        stateLock.unlock()

        guard ensureLinkActive() else { return }
        try? link.send(reqData, context: .resourceRequest)
    }

    private func assemble() {
        stateLock.lock()
        _status = .transferring
        let allParts = parts.compactMap { $0 }
        let totalPartsSnapshot = totalParts
        let adv = _advertisement
        stateLock.unlock()

        guard allParts.count == totalPartsSnapshot, let adv else {
            fail("assembly: missing parts")
            return
        }

        // Inline assembly with specific failure diagnostics. Decrypt, decompress and
        // hash-verify are pure/callout work — done OUTSIDE the lock.
        let encryptedStream = allParts.reduce(Data(), +)
        let decrypted: Data
        do {
            decrypted = try link.decrypt(encryptedStream)
        } catch {
            fail("assembly: decryption failed (\(error))")
            return
        }
        guard decrypted.count > Resource.randomHashSize else {
            fail("assembly: decrypted data too short (\(decrypted.count) bytes)")
            return
        }
        let body = Data(decrypted.dropFirst(Resource.randomHashSize))
        let assembledPlaintext: Data
        if adv.compressed {
            guard let d = Resource.compressor.decompress(body) else {
                fail("assembly: decompression failed (body=\(body.count)B)")
                return
            }
            assembledPlaintext = d
        } else {
            assembledPlaintext = body
        }
        let computedHash = Hashes.fullHash(assembledPlaintext + adv.randomHash)
        guard computedHash == adv.resourceHash else {
            fail("assembly: hash mismatch (computed=\(computedHash.hexString) expected=\(adv.resourceHash.hexString) compressed=\(adv.compressed) plaintext=\(assembledPlaintext.count)B)")
            return
        }
        // Hash matches — construct result.
        let result: Resource.AssemblyResult
        if adv.hasMetadata && assembledPlaintext.count >= 3 {
            let sz = Int(assembledPlaintext[0]) << 16 | Int(assembledPlaintext[1]) << 8 | Int(assembledPlaintext[2])
            guard assembledPlaintext.count >= 3 + sz else {
                fail("assembly: metadata prefix out of range")
                return
            }
            let meta = Data(assembledPlaintext[3 ..< 3 + sz])
            let payload = Data(assembledPlaintext[(3 + sz)...])
            result = Resource.AssemblyResult(payload: payload, metadata: meta)
        } else {
            result = Resource.AssemblyResult(payload: assembledPlaintext, metadata: nil)
        }

        let plaintext = result.payload

        let segIdx = Int(adv.segmentIndex)
        let segTotal = Int(adv.totalSegments)

        if segIdx < segTotal {
            // More segments to come.
            // Accumulate bytes BEFORE sending proof so we're ready when the
            // next ADV arrives synchronously (loopback interfaces cascade instantly).
            stateLock.lock()
            _receivedMetadata = result.metadata
            segmentBuffer.append(plaintext)
            originalHash = Data(adv.originalHash)
            // Preserve metadata from segment 1 (subsequent segments have no metadata).
            if result.metadata != nil { multiSegmentMetadata = result.metadata }
            _status = .idle
            stateLock.unlock()
            stopWatchdog()
            // Stay registered in incomingResources so the next ADV is dispatched
            // to this object directly — do NOT unregister + re-register since that
            // would miss synchronously-cascaded ADVs from loopback interfaces.

            // Same proof basis logic as for the final segment.
            let midProofBasis: Data
            if let meta = result.metadata {
                let sz = meta.count
                var encoded = Data()
                encoded.append(UInt8((sz >> 16) & 0xFF))
                encoded.append(UInt8((sz >>  8) & 0xFF))
                encoded.append(UInt8( sz        & 0xFF))
                encoded.append(contentsOf: meta)
                encoded.append(contentsOf: plaintext)
                midProofBasis = encoded
            } else {
                midProofBasis = plaintext
            }
            let proof = Hashes.fullHash(midProofBasis + adv.resourceHash)
            let proofPacket = adv.resourceHash + proof
            do {
                try link.sendResourceProof(proofPacket)
            } catch {
                fail("proof send failed: \(error)")
            }
            return
        }

        // All segments received — concatenate and deliver.
        stateLock.lock()
        _receivedMetadata = result.metadata
        segmentBuffer.append(plaintext)
        let fullPayload = segmentBuffer.reduce(Data(), +)
        segmentBuffer.removeAll()
        // Use metadata from segment 1 if this was a multi-segment transfer.
        if multiSegmentMetadata != nil {
            _receivedMetadata = multiSegmentMetadata
            multiSegmentMetadata = nil
        }
        let startedSnapshot = startedTransferring
        stateLock.unlock()

        // Proof must be computed over the FULL encoded data (transferData),
        // which includes the metadata prefix when hasMetadata=true.
        // Reconstruct: [3-byte size][meta][payload] when metadata is present.
        let proofBasis: Data
        if let meta = result.metadata {
            let sz = meta.count
            var encoded = Data()
            encoded.append(UInt8((sz >> 16) & 0xFF))
            encoded.append(UInt8((sz >>  8) & 0xFF))
            encoded.append(UInt8( sz        & 0xFF))
            encoded.append(contentsOf: meta)
            encoded.append(contentsOf: plaintext)
            proofBasis = encoded
        } else {
            proofBasis = plaintext
        }

        // Send proof before notifying application.
        let proof = Hashes.fullHash(proofBasis + adv.resourceHash)
        let proofPacket = adv.resourceHash + proof
        do {
            try link.sendResourceProof(proofPacket)
        } catch {
            fail("proof send failed: \(error)")
            return
        }

        if let hook = onAssembledInternal {
            hook(fullPayload, self)
        } else {
            onPayloadReceived?(fullPayload, self)
        }

        // Update link expected rate (mirrors Python Link.resource_concluded).
        if let started = startedSnapshot {
            let duration = Date().timeIntervalSince(started)
            link.resourceConcluded(dataSize: Int(adv.dataSize), duration: duration)
        }

        stateLock.lock(); _status = .complete; stateLock.unlock()
        stopWatchdog()
        link.unregisterIncomingResource(self)
        onComplete?(self)
    }

    /// Aborts the transfer (via `fail`) when the link is no longer active, before
    /// attempting a send. Mirrors Python `Resource.ensure_link()` (commit 3a36c367).
    /// Returns `true` when the link is usable.
    @discardableResult
    private func ensureLinkActive() -> Bool {
        if link.status != .active {
            fail("invalid link state, aborting transfer")
            return false
        }
        return true
    }

    private func fail(_ reason: String) {
        let s = Status.failed(reason: reason)
        stateLock.lock()
        // Idempotent ONLY against re-failing: fail() overrides any other state
        // (including a prior .complete/.rejected), exactly as the original did —
        // the ResourceCancel/LinkDrop tests rely on cancel-after-reject → .failed.
        // The lock adds atomicity; it does not change the state-machine semantics.
        if case .failed = _status { stateLock.unlock(); return }
        _status = s
        let receiver = isReceiver
        let rhash = _resourceHash
        stateLock.unlock()

        stopWatchdog()
        // Notify the peer that this transfer is being aborted so it concludes
        // promptly instead of waiting for its own watchdog timeout. A receiver
        // sends RESOURCE_RCL, a sender sends RESOURCE_ICL — mirrors Python
        // Resource.cancel() (the RCL branch was added in commit bb289744; the
        // ICL branch is long-standing). Only emitted while the link is active
        // and the resource hash is known.
        if link.status == .active, !rhash.isEmpty {
            let cancelContext: Packet.Context = receiver ? .resourceReceiverCancel : .resourceInitiatorCancel
            try? link.send(rhash, context: cancelContext)
        }
        link.unregisterOutgoingResource(self)
        link.unregisterIncomingResource(self)
        onFailed?(self, s)
    }
}
