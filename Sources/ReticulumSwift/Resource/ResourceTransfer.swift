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
    public private(set) var status: Status = .idle
    public private(set) var advertisement: ResourceAdvertisement?

    /// True when this transfer is the RECEIVER of an incoming resource (set once an
    /// advertisement is received). Senders leave this false. Mirrors the inverse of
    /// Python's `Resource.initiator`: on cancel a receiver emits RESOURCE_RCL while a
    /// sender emits RESOURCE_ICL.
    private var isReceiver: Bool = false

    /// Wall-clock time when data transfer began (first REQ sent/received).
    /// Used to compute `link.expectedRate` on completion. Mirrors Python `Resource.started_transferring`.
    private var startedTransferring: Date?

    /// Full 32-byte SHA256 resource hash. Set after send() or receiveAdvertisement().
    public private(set) var resourceHash: Data = Data()

    public var onComplete: ((ResourceTransfer) -> Void)?
    public var onFailed: ((ResourceTransfer, Status) -> Void)?
    /// Receiver-side: fires with the reassembled plaintext once verified.
    public var onPayloadReceived: ((Data, ResourceTransfer) -> Void)?

    // MARK: - Accessor properties (mirrors Python Resource getter methods)

    /// Transfer progress as a value from 0.0 to 1.0.
    /// Mirrors Python's `Resource.get_progress()`.
    public var progress: Double {
        if case .complete = status { return 1.0 }
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
    public var partCount: Int { totalParts > 0 ? totalParts : encryptedSegments.count }

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

    /// Set on the receiver side after successful assembly when the sender included metadata.
    /// The bytes are the raw pre-packed metadata (without the 3-byte size prefix).
    public private(set) var receivedMetadata: Data?

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
        t.resume()
        watchdogTimer = t
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    private func watchdogTick() {
        guard !status.isTerminal else { stopWatchdog(); return }
        let sinceActivity = Date().timeIntervalSince(lastActivity)
        guard sinceActivity >= retryTimeout else { return }

        if retriesLeft > 0 {
            retriesLeft -= 1
            lastActivity = Date()
            switch status {
            case .advertised:
                // No REQ received — retransmit ADV.
                if let adv = advertisement { try? link.send(adv.pack(), context: .resourceAdvertisement) }
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
            pendingSegments = Array(chunks.dropFirst())
            segmentIndex = 1
            totalSegments = chunks.count
            segmentMetadata = metadata
            segmentRequestID = requestID
            segmentIsRequest = isRequest
            segmentIsResponse = isResponse
            segmentAutoCompress = autoCompress

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
        let resource = try Resource(link: link, payload: payload, metadata: metadata,
                                    segmentSize: segmentSize, autoCompress: autoCompress)
        encryptedSegments = resource.encryptedSegments
        mapHashes = resource.mapHashes
        randomHash = resource.randomHash
        resourceHash = resource.resourceHash
        expectedProof = resource.expectedProof

        // For segment 1, set overallOriginalHash = first segment's resource hash.
        if segmentIndex == 1 { overallOriginalHash = resource.resourceHash }

        let adv = ResourceAdvertisement(
            transferSize: UInt64(resource.transferSize),
            dataSize: UInt64(resource.dataSize),
            partCount: UInt64(resource.partCount),
            resourceHash: resource.resourceHash,
            randomHash: resource.randomHash,
            originalHash: overallOriginalHash,
            segmentIndex: UInt64(segmentIndex),
            totalSegments: UInt64(totalSegments),
            requestID: requestID ?? segmentRequestID,
            hashmap: resource.mapHashes.reduce(Data(), +),
            encrypted: true,
            compressed: resource.isCompressed,
            split: totalSegments > 1,
            isRequest: isRequest || segmentIsRequest,
            isResponse: isResponse || segmentIsResponse,
            hasMetadata: resource.hasMetadata
        )
        advertisement = adv

        link.registerOutgoingResource(self)
        status = .advertised
        retriesLeft = maxAdvRetries
        lastActivity = Date()
        guard ensureLinkActive() else { return }
        try link.send(adv.pack(), context: .resourceAdvertisement)
        startWatchdog()
    }

    /// Called by Link when a RESOURCE_REQ arrives for our resource hash.
    internal func handleRequest(_ data: Data) {
        guard status == .advertised || status == .transferring || status == .awaitingProof else { return }
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

        if status != .transferring {
            status = .transferring
            if startedTransferring == nil { startedTransferring = Date() }
        }
        lastActivity = Date()
        retriesLeft = maxRetries

        // Send the requested parts, searching only within the collision-guard window
        // around the receiver's consecutive height. A windowed search ensures the
        // correct part is sent even when a 4-byte map-hash collides with a distant
        // part elsewhere in the resource. Mirrors Python `Resource.request`.
        let sendStart = min(receiverMinConsecutiveHeight, mapHashes.count)
        let sendEnd = min(receiverMinConsecutiveHeight + ResourceAdvertisement.collisionGuardSize, mapHashes.count)
        for idx in sendStart ..< sendEnd {
            let mapHash = mapHashes[idx]
            if requestedHashes.contains(mapHash) {
                try? link.sendResourcePart(encryptedSegments[idx])
                sentMapHashes.insert(mapHash)
            }
        }

        // If the receiver exhausted its known hashmap, send the next HMU segment.
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
            guard partIndex % hml == 0 else {
                // Next segment is not aligned to a HASHMAP_MAX_LEN boundary — the
                // receiver's request is out of sequence. Abort, as Python does.
                cancel(reason: "resource sequencing error")
                return
            }
            let segment = partIndex / hml
            let hashmapStart = segment * hml
            let hashmapEnd = min((segment + 1) * hml, mapHashes.count)
            guard hashmapStart < hashmapEnd else {
                // Degenerate/empty HMU request — abort rather than silently skip.
                // Mirrors Python `request()` (`if not hashmap: cancel()`).
                cancel(reason: "resource HMU error")
                return
            }
            let hmuHashmap = mapHashes[hashmapStart ..< hashmapEnd].reduce(Data(), +)
            let hmuPayload = resourceHash + MsgPack.encode(.array([
                .uint(UInt64(segment)),
                .bytes(hmuHashmap)
            ]))
            guard ensureLinkActive() else { return }
            try? link.send(hmuPayload, context: .resourceHashmapUpdate)
        }

        // If proof already arrived (loopback) leave the completed status alone.
        guard status != .complete, status != .rejected else { return }

        // Advance to awaitingProof once every segment has been sent at least once.
        if sentMapHashes.count == mapHashes.count {
            status = .awaitingProof
        }
    }

    /// Called by Link when a RESOURCE_PRF proof arrives for our resource hash.
    internal func validateProof(_ proofData: Data) {
        // Proof wire format: hash (32 bytes) || sha256(transferData + hash) (32 bytes)
        guard proofData.count == Constants.hashLength * 2 else {
            fail("proof wrong length: \(proofData.count)")
            return
        }
        let receivedProof = proofData.suffix(Constants.hashLength)
        guard Data(receivedProof) == expectedProof else {
            fail("proof mismatch")
            return
        }
        stopWatchdog()
        link.unregisterOutgoingResource(self)

        // Update link expected rate (mirrors Python Link.resource_concluded).
        if let started = startedTransferring {
            let duration = Date().timeIntervalSince(started)
            link.resourceConcluded(dataSize: Int(advertisement?.dataSize ?? 0), duration: duration)
        }

        // Multi-segment: if more segments remain, advance and advertise next.
        if !pendingSegments.isEmpty {
            let next = pendingSegments.removeFirst()
            segmentIndex += 1
            status = .idle
            do {
                try sendSegment(
                    payload: next,
                    metadata: nil,  // metadata only on first segment
                    segmentSize: Constants.mdu,
                    requestID: segmentRequestID,
                    isRequest: segmentIsRequest,
                    isResponse: segmentIsResponse,
                    autoCompress: segmentAutoCompress
                )
            } catch {
                fail("multi-segment next: \(error)")
            }
            return
        }

        status = .complete
        onComplete?(self)
    }

    internal func reject() {
        status = .rejected
        stopWatchdog()
        link.unregisterOutgoingResource(self)
        let s = Status.rejected
        onFailed?(self, s)
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
        isReceiver = true
        advertisement = adv
        resourceHash = adv.resourceHash
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
        status = .transferring
        retriesLeft = maxRetries
        lastActivity = Date()
        if startedTransferring == nil { startedTransferring = Date() }
        startWatchdog()
        sendRequest()
    }

    /// Called by Link for each inbound RESOURCE data part (raw pre-encrypted bytes).
    internal func receivePart(_ data: Data) {
        guard status == .transferring else { return }
        lastActivity = Date()
        retriesLeft = maxRetries

        let partHash = Hashes.fullHash(data + randomHashForReceiver()).prefix(ResourceTransfer.mapHashLength)
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

        if receivedCount == totalParts {
            assemble()
            return
        }

        if outstandingParts == 0 {
            if window < ResourceTransfer.windowMax { window += 1 }
            sendRequest()
        }
    }

    /// Called by Link when a RESOURCE_HMU arrives (decrypted plaintext starting with resourceHash).
    internal func handleHashmapUpdate(_ data: Data) {
        guard status == .transferring else { return }
        // Only process a hashmap update we actually requested; unsolicited or
        // duplicate HMUs are ignored. Mirrors Python `hashmap_update_packet`
        // gating on `self.waiting_for_hmu` (commit 3a36c367).
        guard waitingForHMU else { return }
        guard data.count > Constants.hashLength else { return }
        let payload = data.dropFirst(Constants.hashLength)
        guard case .array(let arr) = (try? MsgPack.decode(Data(payload))),
              arr.count >= 2,
              case .uint(let segIdx) = arr[0],
              case .bytes(let hmap) = arr[1] else { return }

        // An HMU carrying fewer than one full map-hash is invalid — abort the
        // transfer. Mirrors Python `hashmap_update` (`if hashes < 1: cancel()`).
        guard hmap.count >= ResourceTransfer.mapHashLength else {
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

    private func randomHashForReceiver() -> Data {
        advertisement?.randomHash ?? Data()
    }

    private func sendRequest() {
        guard !waitingForHMU else { return }
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
        reqData.append(contentsOf: resourceHash)
        reqData.append(contentsOf: requestedHashes)

        guard ensureLinkActive() else { return }
        try? link.send(reqData, context: .resourceRequest)
    }

    private func assemble() {
        status = .transferring
        let allParts = parts.compactMap { $0 }
        guard allParts.count == totalParts, let adv = advertisement else {
            fail("assembly: missing parts")
            return
        }

        // Inline assembly with specific failure diagnostics.
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

        receivedMetadata = result.metadata
        let plaintext = result.payload

        let segIdx = Int(adv.segmentIndex)
        let segTotal = Int(adv.totalSegments)

        if segIdx < segTotal {
            // More segments to come.
            // Accumulate bytes BEFORE sending proof so we're ready when the
            // next ADV arrives synchronously (loopback interfaces cascade instantly).
            segmentBuffer.append(plaintext)
            originalHash = Data(adv.originalHash)
            // Preserve metadata from segment 1 (subsequent segments have no metadata).
            if result.metadata != nil { multiSegmentMetadata = result.metadata }
            status = .idle
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
        segmentBuffer.append(plaintext)
        let fullPayload = segmentBuffer.reduce(Data(), +)
        segmentBuffer.removeAll()

        // Use metadata from segment 1 if this was a multi-segment transfer.
        if multiSegmentMetadata != nil {
            receivedMetadata = multiSegmentMetadata
            multiSegmentMetadata = nil
        }

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
        if let started = startedTransferring {
            let duration = Date().timeIntervalSince(started)
            link.resourceConcluded(dataSize: Int(adv.dataSize), duration: duration)
        }

        status = .complete
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
        guard case .failed = status else {
            let s = Status.failed(reason: reason)
            status = s
            stopWatchdog()
            // Notify the peer that this transfer is being aborted so it concludes
            // promptly instead of waiting for its own watchdog timeout. A receiver
            // sends RESOURCE_RCL, a sender sends RESOURCE_ICL — mirrors Python
            // Resource.cancel() (the RCL branch was added in commit bb289744; the
            // ICL branch is long-standing). Only emitted while the link is active
            // and the resource hash is known.
            if link.status == .active, !resourceHash.isEmpty {
                let cancelContext: Packet.Context = isReceiver ? .resourceReceiverCancel : .resourceInitiatorCancel
                try? link.send(resourceHash, context: cancelContext)
            }
            link.unregisterOutgoingResource(self)
            link.unregisterIncomingResource(self)
            onFailed?(self, s)
            return
        }
    }
}
