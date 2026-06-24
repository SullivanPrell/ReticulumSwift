import XCTest
@testable import ReticulumSwift

/// Tests for large resource transfers (above MAX_EFFICIENT_SIZE) that use multi-segment protocol.
final class LargeResourceTests: XCTestCase {

    var aT: Transport!; var bT: Transport!

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    private func establishLink() throws -> (Link, Link) {
        aT = Transport(); bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["large"])
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)
        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aT.onLinkEstablished = { _ in aE.fulfill() }; bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aLink, bLink)
    }

    // Use a small testSegmentSizeOverride to force multi-segment behavior
    func testMultiSegmentTransfer() throws {
        let (aLink, bLink) = try establishLink()
        // Force 2 segments: payload > 100 bytes forces split at 100
        let payload = Data(repeating: 0xAA, count: 250)

        let done = expectation(description: "complete")
        var received: Data?

        let sender = ResourceTransfer(link: aLink)
        sender.testSegmentSizeOverride = 100  // force multi-segment at 100 bytes
        sender.onComplete = { _ in done.fulfill() }

        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()
        receiver.onPayloadReceived = { data, _ in received = data }

        try sender.send(payload: payload)
        wait(for: [done], timeout: 5.0)

        XCTAssertEqual(received, payload, "multi-segment transfer must preserve data")
    }

    func testSingleSegmentForSmallPayload() throws {
        let (aLink, bLink) = try establishLink()
        let payload = Data(repeating: 0xBB, count: 50)

        let done = expectation(description: "complete")
        var received: Data?

        let sender = ResourceTransfer(link: aLink)
        sender.onComplete = { _ in done.fulfill() }
        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()
        receiver.onPayloadReceived = { data, _ in received = data }

        try sender.send(payload: payload)
        wait(for: [done], timeout: 3.0)
        XCTAssertEqual(received, payload)
    }

    func testProgressReportingDuringTransfer() throws {
        let (aLink, bLink) = try establishLink()
        let payload = Data(repeating: 0xCC, count: 200)

        let done = expectation(description: "complete")
        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()
        let sender = ResourceTransfer(link: aLink)
        sender.testSegmentSizeOverride = 50  // small segments for progress tracking
        sender.onComplete = { _ in done.fulfill() }
        receiver.onPayloadReceived = { _, _ in }

        try sender.send(payload: payload)
        wait(for: [done], timeout: 5.0)

        XCTAssertEqual(sender.status, .complete)
        XCTAssertEqual(receiver.progress, 1.0, accuracy: 0.01)
    }

    // MARK: - Multi-segment hashmap (HASHMAP_MAX_LEN) parity

    /// The hashmap segment length must mirror Python's
    /// `HASHMAP_MAX_LEN = floor((Link.MDU - OVERHEAD)/MAPHASH_LEN) = 74`, not the
    /// window-max (10). The collision-guard window must be `2*75 + 74 = 224`.
    func testHashmapConstantsMatchPython() {
        XCTAssertEqual(ResourceAdvertisement.hashmapMaxLength, 74)
        XCTAssertEqual(ResourceAdvertisement.collisionGuardSize, 224)
    }

    /// A resource advertisement must carry only the first `HASHMAP_MAX_LEN` part-hashes
    /// on the wire (the rest are delivered via HMU). Before the fix, `pack()` emitted the
    /// whole hashmap, which both overflows the link MDU and mis-indexes HMU segments
    /// against a Python peer. Mirrors Python `ResourceAdvertisement.pack(segment=0)`.
    func testAdvertisementCarriesOnlyFirstHashmapSegment() throws {
        let parts = 200
        // 4 distinct, position-encoding bytes per part so ordering is verifiable.
        let fullHashmap = Data((0..<parts).flatMap { p -> [UInt8] in
            [UInt8(truncatingIfNeeded: p), UInt8(truncatingIfNeeded: p >> 8), 0xAB, 0xCD]
        })
        let adv = ResourceAdvertisement(
            transferSize: 99_999, dataSize: 99_999, partCount: UInt64(parts),
            resourceHash: Data(repeating: 0x11, count: 32),
            randomHash: Data(repeating: 0x22, count: 32),
            originalHash: Data(repeating: 0x33, count: 32),
            segmentIndex: 1, totalSegments: 1,
            hashmap: fullHashmap, encrypted: true
        )

        let hml = ResourceAdvertisement.hashmapMaxLength
        let mhl = ResourceAdvertisement.mapHashLength

        // Default pack() carries only the first segment (parts 0..73).
        let seg0 = try ResourceAdvertisement.unpack(adv.pack())
        XCTAssertEqual(seg0.hashmap.count, hml * mhl)
        XCTAssertEqual(seg0.hashmap, Data(fullHashmap.prefix(hml * mhl)))

        // Segment index 1 carries the next window (parts 74..147).
        let seg1 = try ResourceAdvertisement.unpack(adv.pack(segment: 1))
        let start = hml * mhl
        let end = min(2 * hml, parts) * mhl
        XCTAssertEqual(seg1.hashmap, Data(fullHashmap[start..<end]))
    }

    /// End-to-end transfer of a single-segment resource with far more parts than fit in
    /// one advertisement (>2 hashmap segments). This forces the receiver to pull later
    /// hashmap segments via HMU packets and the sender to emit them indexed by
    /// `partIndex / HASHMAP_MAX_LEN`. It only completes when both sides agree on the
    /// segment length (74) — the regression this guards against.
    func testLargeSingleSegmentResourceUsesHashmapUpdates() throws {
        let (aLink, bLink) = try establishLink()

        // ~13 KB of incompressible (SHA-chained) data so it stays a single segment but
        // splits into >148 parts at an 80-byte part size — spanning 3 hashmap segments.
        var payload = Data()
        var seed = Data(repeating: 0x5A, count: 32)
        while payload.count < 13_000 {
            seed = Hashes.fullHash(seed)
            payload.append(seed)
        }
        payload = Data(payload.prefix(13_000))

        let done = expectation(description: "complete")
        var received: Data?

        let sender = ResourceTransfer(link: aLink)
        sender.onComplete = { _ in done.fulfill() }
        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()
        receiver.onPayloadReceived = { data, _ in received = data }

        // 80-byte parts => >162 parts, spanning hashmap segments 0, 1 and 2.
        try sender.send(payload: payload, segmentSize: 80, autoCompress: false)
        wait(for: [done], timeout: 15.0)

        XCTAssertGreaterThan(sender.partCount, 2 * ResourceAdvertisement.hashmapMaxLength,
                             "test must exceed two hashmap segments to exercise HMU")
        XCTAssertEqual(sender.status, .complete)
        XCTAssertEqual(received, payload, "large multi-hashmap-segment transfer must preserve data")
    }
}
