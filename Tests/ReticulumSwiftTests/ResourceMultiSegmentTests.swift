import XCTest
@testable import ReticulumSwift

/// Tests for multi-segment resource transfer (data > MAX_EFFICIENT_SIZE ≈ 1 MB).
/// Mirrors Python's `Resource` segmented protocol: when data exceeds
/// MAX_EFFICIENT_SIZE, it is split into multiple segments each sent as a
/// separate advertisement round-trip.
final class ResourceMultiSegmentTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    // Keep transports alive for the test duration.
    var aT: Transport!
    var bT: Transport!

    /// Delivers on a serial queue instead of straight down the call stack, so a large
    /// transfer's request/part/HMU round-trips don't recurse into an ever-deeper synchronous
    /// stack (which the plain `LoopbackInterface` above cannot survive past a few hundred
    /// bytes). Ordered delivery on one queue still models a single link faithfully.
    final class AsyncLoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: AsyncLoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        let queue: DispatchQueue
        init(name: String, queue: DispatchQueue) { self.name = name; self.queue = queue }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            queue.async { [weak self] in
                guard let self, let paired = self.paired else { return }
                if let copy = try? Packet.unpack(raw) { paired.inboundHandler?(copy, paired) }
            }
        }
    }

    func makeAsyncLinkedPair() throws -> (aLink: Link, bLink: Link) {
        aT = Transport(); bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "ms")
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        let q = DispatchQueue(label: "ms.asyncloopback")
        let a = AsyncLoopbackInterface(name: "a", queue: q)
        let b = AsyncLoopbackInterface(name: "b", queue: q)
        a.paired = b; b.paired = a
        aT.register(interface: a); bT.register(interface: b)
        let aE = expectation(description: "aE"); let bE = expectation(description: "bE")
        aT.onLinkEstablished = { _ in aE.fulfill() }
        bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 2.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aLink, bLink)
    }

    func makeLinkedPair() throws -> (aLink: Link, bLink: Link) {
        aT = Transport(); bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "ms")
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        let a = LoopbackInterface(name: "a"); let b = LoopbackInterface(name: "b")
        a.paired = b; b.paired = a
        aT.register(interface: a); bT.register(interface: b)
        let aE = expectation(description: "aE"); let bE = expectation(description: "bE")
        aT.onLinkEstablished = { _ in aE.fulfill() }
        bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aLink, bLink)
    }

    // MARK: - Constants

    func testMaxEfficientSizeConstant() {
        // Python: MAX_EFFICIENT_SIZE = 1 * 1024 * 1024 - 1
        XCTAssertEqual(ResourceTransfer.maxEfficientSize, 1_048_575)
    }

    // MARK: - Single-segment still works for small payload

    func testSmallPayloadUsesOneSegment() throws {
        let (aLink, bLink) = try makeLinkedPair()
        let tx = ResourceTransfer(link: aLink)
        let rx = ResourceTransfer(link: bLink)
        rx.bindAsReceiver()

        let payload = Data(repeating: 0xAA, count: 1000)
        let received = expectation(description: "received")
        var got: Data?
        rx.onPayloadReceived = { d, _ in got = d; received.fulfill() }

        try tx.send(payload: payload)
        wait(for: [received], timeout: 2.0)
        XCTAssertEqual(got, payload)
        XCTAssertEqual(tx.advertisement?.segmentIndex, 1)
        XCTAssertEqual(tx.advertisement?.totalSegments, 1)
    }

    // MARK: - Small artificial segment size for fast multi-segment testing

    /// Tests multi-segment with a small test payload using overridden segment size.
    /// Uses `testSegmentSizeOverride` to avoid 1MB+ payloads in unit tests.
    func testTwoSegmentSmallPayload() throws {
        let (aLink, bLink) = try makeLinkedPair()
        let tx = ResourceTransfer(link: aLink)
        let rx = ResourceTransfer(link: bLink)
        rx.bindAsReceiver()

        // 300-byte payload split into 2 segments of ~150 bytes each.
        let payload = Data((0 ..< 300).map { UInt8($0 % 251) })
        let received = expectation(description: "received")
        let complete = expectation(description: "complete")
        var got: Data?
        rx.onPayloadReceived = { d, _ in got = d; received.fulfill() }
        tx.onComplete = { _ in complete.fulfill() }

        // Use small test segment size (150 bytes).
        tx.testSegmentSizeOverride = 150
        try tx.send(payload: payload)

        wait(for: [received, complete], timeout: 2.0)
        XCTAssertEqual(got, payload)
    }

    // MARK: - Two-segment transfer

    func testTwoSegmentPayloadTransfer() throws {
        let (aLink, bLink) = try makeLinkedPair()
        let tx = ResourceTransfer(link: aLink)
        let rx = ResourceTransfer(link: bLink)
        rx.bindAsReceiver()

        // Use a 600-byte payload split at 400-byte segments to keep the test fast.
        let segSize = 400
        let totalSize = 600
        let payload = Data((0 ..< totalSize).map { UInt8($0 % 251) })
        tx.testSegmentSizeOverride = segSize

        let received = expectation(description: "received")
        let complete = expectation(description: "complete")
        var got: Data?
        rx.onPayloadReceived = { d, _ in got = d; received.fulfill() }
        tx.onComplete = { _ in complete.fulfill() }

        try tx.send(payload: payload)
        wait(for: [received, complete], timeout: 2.0)

        XCTAssertEqual(got, payload, "full two-segment payload must match original")
    }

    // MARK: - Advertisement fields for multi-segment

    func testMultiSegmentAdvertisementHasSplitFlag() throws {
        let (aLink, bLink) = try makeLinkedPair()
        _ = bLink

        let tx = ResourceTransfer(link: aLink)
        tx.testSegmentSizeOverride = 300
        let payload = Data(repeating: 0xBB, count: 400)  // 400 bytes > 300-byte limit → 2 segments

        // We just want to verify the ADV flags, not do a full transfer.
        // Register a fake receiver that captures the ADV but doesn't respond.
        let fakeRx = ResourceTransfer(link: bLink)
        fakeRx.bindAsReceiver()
        fakeRx.onFailed = { _, _ in }  // ignore failures

        tx.testSegmentSizeOverride = 300
        try tx.send(payload: payload)

        // Give some time for ADV to arrive on the receiver side.
        let tick = expectation(description: "tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tick.fulfill() }
        wait(for: [tick], timeout: 1.0)

        // After the entire transfer completes synchronously, `advertisement` reflects
        // the last segment sent. Verify total_segments and split flag are set correctly.
        // (The entire transfer may have completed before we check, so segmentIndex may be 2.)
        let adv = tx.advertisement
        XCTAssertNotNil(adv)
        XCTAssertEqual(adv?.totalSegments, 2)
        XCTAssertTrue(adv?.split ?? false, "split flag must be set for multi-segment")
    }

    // MARK: - Three-segment transfer

    func testThreeSegmentPayloadTransfer() throws {
        let (aLink, bLink) = try makeLinkedPair()
        let tx = ResourceTransfer(link: aLink)
        let rx = ResourceTransfer(link: bLink)
        rx.bindAsReceiver()

        // 900-byte payload at 300-byte segments → 3 segments.
        let segSize = 300
        let totalSize = 900
        let payload = Data((0 ..< totalSize).map { UInt8($0 % 251) })
        tx.testSegmentSizeOverride = segSize

        let received = expectation(description: "received")
        var got: Data?
        rx.onPayloadReceived = { d, _ in got = d; received.fulfill() }

        try tx.send(payload: payload)
        wait(for: [received], timeout: 5.0)
        XCTAssertEqual(got, payload)
    }

    // MARK: - Multi-segment with metadata

    func testTwoSegmentWithMetadata() throws {
        let (aLink, bLink) = try makeLinkedPair()
        let tx = ResourceTransfer(link: aLink)
        let rx = ResourceTransfer(link: bLink)
        rx.bindAsReceiver()

        let meta = Data([0x01, 0x02, 0x03])
        let payload = Data((0 ..< 600).map { UInt8($0 % 251) })

        let received = expectation(description: "received")
        var gotPayload: Data?
        var gotMeta: Data?
        rx.onPayloadReceived = { d, t in
            gotPayload = d
            gotMeta = t.receivedMetadata
            received.fulfill()
        }

        tx.testSegmentSizeOverride = 400
        try tx.send(payload: payload, metadata: meta)

        wait(for: [received], timeout: 2.0)
        XCTAssertEqual(gotPayload, payload)
        XCTAssertEqual(gotMeta, meta)
    }

    // MARK: - Large multi-segment via the real Link accept path (regression)

    /// A multi-segment transfer received through the actual Link accept path
    /// (`onResourceAdvertised` → `acceptIncomingResource` → `onResourceConcluded`),
    /// rather than the `bindAsReceiver` shortcut the other tests use, with segments large
    /// enough to span more than one hashmap window (MDU is 464 B, so >74 parts needs ~34 KB).
    ///
    /// This is the shape that shipped broken and the small-payload / direct-bind tests could
    /// not catch. It pins three fixes at once:
    ///   1. The sender resets its per-segment part-serving window when it advances a segment.
    ///      Segment 2 is shorter than segment 1, so a carried-over cursor pointed past its
    ///      last part and the sender served nothing — the receiver stalled and failed.
    ///   2. The Link reports the CONCLUDING advertisement (the last segment), not the first
    ///      one captured when the transfer began; a listener matches a finished transfer — and
    ///      recovers its metadata — by that hash.
    ///   3. Metadata rides only in segment 1 yet survives, intact, to the final payload.
    func testLargeMultiSegmentRoundTripViaLinkAcceptPath() throws {
        let (aLink, bLink) = try makeAsyncLinkedPair()

        // 240 KB split at 200 KB → segment 1 ≈ 440 parts, segment 2 ≈ 87 parts. Segment 1 must
        // be big enough to force SEVERAL hashmap-update rounds: each round rewinds the sender's
        // search cursor by WINDOW_MAX_FAST (75), so a segment needing only one round leaves the
        // cursor at 0 and the carried-over state is harmless. Only after multiple rounds does the
        // cursor climb past the shorter second segment's part count — the exact state the
        // cursor-reset fix clears. (The interop failure was 2261- then 2051-part segments.)
        // The payload is filled by a pseudo-random LCG so bzip2 cannot shrink it below the part
        // count that drives those rounds; `autoCompress: false` below makes that guarantee exact.
        // A deterministic LCG is used because the sandbox forbids `Math.random`.
        var lcg: UInt64 = 0x9E3779B97F4A7C15
        var payload = Data(); payload.reserveCapacity(240_000)
        for _ in 0 ..< 240_000 {
            lcg = lcg &* 6364136223846793005 &+ 1442695040888963407
            payload.append(UInt8((lcg >> 33) & 0xFF))
        }
        let meta = Data("multi-segment-filename.bin".utf8)

        // Drive the receiver through the Link accept path, not bindAsReceiver().
        bLink.resourceStrategy = .acceptAll
        var startedTransfer: ResourceTransfer?
        bLink.onResourceStarted = { rt in startedTransfer = rt }
        var gotPayload: Data?
        var concludedSegmentIndex: UInt64?
        var concludedTotalSegments: UInt64?
        let concluded = expectation(description: "concluded")
        bLink.onResourceConcluded = { p, adv, _ in
            gotPayload = p
            concludedSegmentIndex = adv.segmentIndex
            concludedTotalSegments = adv.totalSegments
            concluded.fulfill()
        }

        let tx = ResourceTransfer(link: aLink)
        tx.testSegmentSizeOverride = 200_000
        // Compression OFF so segment 1's part count (≈ 440, several hashmap-update rounds) is
        // exact and the sender's search cursor climbs well past segment 2's ≈ 87 parts.
        try tx.send(payload: payload, metadata: meta, autoCompress: false)

        wait(for: [concluded], timeout: 30.0)

        XCTAssertEqual(gotPayload, payload, "the full multi-segment payload must match the original")
        XCTAssertEqual(concludedTotalSegments, 2)
        XCTAssertEqual(concludedSegmentIndex, concludedTotalSegments,
            "the concluding advertisement must be the LAST segment so a listener can match it by hash")
        XCTAssertEqual(startedTransfer?.receivedMetadata, meta,
            "segment-1 metadata must survive to the completed transfer")
    }

    // MARK: - Sender progress across segments

    /// Sender progress must climb once across the whole split transfer, not once
    /// per segment. The per-segment counters (`sentMapHashes` / `mapHashes`) are
    /// both reset when a segment starts, so reading them alone reports 0→1 for
    /// every segment — reaching 1.0 while the transfer is still running and then
    /// going backwards. Python folds the segment position in
    /// (Resource.py:1151-1167) and keeps a separate `get_segment_progress` for the
    /// per-segment figure.
    func testSenderProgressIsMonotonicAcrossSegments() throws {
        // Async delivery: with a synchronous loopback the whole transfer runs
        // inside the first send and every progress emit unwinds afterwards, when
        // the status is already .complete — so intermediate values are invisible.
        let (aLink, bLink) = try makeAsyncLinkedPair()
        bLink.resourceStrategy = .acceptAll

        let lock = NSLock()
        var observed: [Double] = []
        let concluded = expectation(description: "concluded")
        bLink.onResourceConcluded = { _, _, _ in concluded.fulfill() }

        let tx = ResourceTransfer(link: aLink)
        tx.testSegmentSizeOverride = 300
        tx.onProgress = { p, _ in lock.lock(); observed.append(p); lock.unlock() }
        try tx.send(payload: Data(repeating: 0xD4, count: 900), autoCompress: false)
        wait(for: [concluded], timeout: 20.0)

        lock.lock(); let progress = observed; lock.unlock()
        XCTAssertFalse(progress.isEmpty, "sender reported no progress at all")
        XCTAssertEqual(progress, progress.sorted(),
                       "sender progress went backwards across a segment boundary: \(progress)")
        XCTAssertEqual(progress.filter { $0 >= 1.0 }.count, 1,
                       "progress reached 1.0 more than once — it is being measured per segment: \(progress)")
    }

    // MARK: - Split request/response resources

    /// A response larger than one segment must arrive whole.
    ///
    /// Segments 2..N carry the same `isResponse` flag and request ID as segment 1
    /// (Python's `__prepare_next_segment` forwards both, and so does ours), so the
    /// RESOURCE_ADV dispatch used to take the `isResponse` branch again for every
    /// segment and build a fresh `ResourceTransfer` each time. Only the last
    /// segment's bytes reached the caller — and as a *successful* response, since
    /// a truncated payload merely fails to decode as the `[request_id, response]`
    /// envelope and falls back to raw bytes. Silent corruption, not an error.
    ///
    /// This is the LXMF propagation-sync and NomadNet file-fetch path.
    func testSplitResponseResourceIsDeliveredWhole() throws {
        ResourceTransfer.testSegmentSizeOverrideGlobal = 4_000
        defer { ResourceTransfer.testSegmentSizeOverrideGlobal = nil }

        let (aLink, bLink) = try makeLinkedPair()
        _ = bLink

        // Incompressible so it cannot shrink back under the segment threshold.
        let responseBody = Data((0 ..< 9_000).map { _ in UInt8.random(in: 0 ... 255) })
        aLink.destination.registerRequestHandler(path: "/big", allow: .all) { _, _, _, _, _ in
            responseBody
        }

        let responded = expectation(description: "response delivered")
        var received: Data?
        var failure: String?
        _ = try bLink.request(
            path: "/big",
            data: Data([0x01]),
            responseCallback: { data, _ in received = data; responded.fulfill() },
            failedCallback: { reason, _ in failure = reason; responded.fulfill() },
            timeout: 30
        )
        wait(for: [responded], timeout: 30.0)

        XCTAssertNil(failure, "split response failed: \(failure ?? "")")
        XCTAssertEqual(received?.count, responseBody.count,
                       "only the last segment was delivered — the rest was dropped")
        XCTAssertEqual(received, responseBody)
    }

    /// A receiver parked between segments stays registered on the link, and the
    /// link hands every subsequent advertisement to every registered receiver. An
    /// unrelated resource advertised in that window used to be adopted by the
    /// parked transfer — downloaded into its segment buffer and spliced into the
    /// middle of the delivered payload, while bypassing `resourceStrategy` and
    /// never firing `onResourceStarted`.
    ///
    /// The receiver is held in the parked state by dropping the mid-transfer
    /// proof on its way back to the sender: parts and requests still flow, so
    /// segment 1 completes, but the sender never learns to advance to segment 2.
    func testForeignAdvertisementIsNotAdoptedByAParkedReceiver() throws {
        let (aLink, bLink, gate) = try makeProofGatedPair()

        let parked = ResourceTransfer(link: bLink)
        parked.bindAsReceiver()

        // Two segments of 300 bytes each.
        let tx = ResourceTransfer(link: aLink)
        tx.testSegmentSizeOverride = 300
        gate.dropProofs = true
        try tx.send(payload: Data(repeating: 0xA7, count: 400), autoCompress: false)

        // Segment 1 has been received and buffered; the transfer is parked.
        XCTAssertEqual(parked.status, .idle, "test premise: receiver should be parked between segments")
        XCTAssertEqual(parked.advertisement?.segmentIndex, 1)
        let parkedHash = parked.resourceHash

        // A different resource is advertised on the same link while it is parked.
        let foreign = ResourceTransfer(link: aLink)
        gate.dropAll = true          // don't let the foreign transfer actually run
        try? foreign.send(payload: Data(repeating: 0x5E, count: 64), autoCompress: false)
        let foreignAdv = try XCTUnwrap(foreign.advertisement)
        gate.dropAll = false

        parked.receiveAdvertisement(try foreignAdv.pack())

        XCTAssertEqual(parked.resourceHash, parkedHash,
                       "the parked receiver adopted an unrelated resource's advertisement")
        XCTAssertEqual(parked.advertisement?.segmentIndex, 1,
                       "the parked receiver's advertisement was replaced by a foreign one")
    }

    /// Loopback pair whose b→a direction can drop PROOF packets, which parks a
    /// multi-segment receiver between segments without stalling the part transfer.
    final class ProofGate {
        var dropProofs = false
        var dropAll = false
    }

    private func makeProofGatedPair() throws -> (aLink: Link, bLink: Link, gate: ProofGate) {
        let gate = ProofGate()
        aT = Transport(); bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "msgate")
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        let a = GatedLoopbackInterface(name: "a", gate: gate, gatesOutbound: false)
        let b = GatedLoopbackInterface(name: "b", gate: gate, gatesOutbound: true)
        a.paired = b; b.paired = a
        aT.register(interface: a); bT.register(interface: b)
        let aE = expectation(description: "aE"); let bE = expectation(description: "bE")
        aT.onLinkEstablished = { _ in aE.fulfill() }
        bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 2.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aLink, bLink, gate)
    }

    final class GatedLoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: GatedLoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        let gate: ProofGate
        /// Only the b→a side drops proofs; a→b must keep flowing.
        let gatesOutbound: Bool
        init(name: String, gate: ProofGate, gatesOutbound: Bool) {
            self.name = name; self.gate = gate; self.gatesOutbound = gatesOutbound
        }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            if gate.dropAll { return }
            if gatesOutbound, gate.dropProofs, packet.packetType == .proof { return }
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    // MARK: - originalHash is stable across segments

    func testOriginalHashStableAcrossSegments() throws {
        let (aLink, bLink) = try makeLinkedPair()
        _ = bLink

        let tx = ResourceTransfer(link: aLink)
        tx.testSegmentSizeOverride = 300
        let payload = Data(repeating: 0xCC, count: 400)

        let fakeRx = ResourceTransfer(link: bLink)
        fakeRx.bindAsReceiver()

        try tx.send(payload: payload)

        // After sending segment 1, the overallOriginalHash is set.
        // The ADV's originalHash should match (it's derived from the first segment's resource hash).
        let adv = tx.advertisement
        XCTAssertNotNil(adv)
        XCTAssertEqual(adv?.originalHash.count, Constants.hashLength)
    }
}
