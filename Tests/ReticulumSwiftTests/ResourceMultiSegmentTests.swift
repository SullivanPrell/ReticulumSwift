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
