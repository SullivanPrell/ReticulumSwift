import XCTest
@testable import ReticulumSwift

/// Parity tests for RNS 1.3.9 Resource safeguards (commits bb289744 / 3a36c367):
/// - a receiver that cancels an in-progress transfer emits RESOURCE_RCL (wire)
/// - ResourceAdvertisement.unpack rejects an oversized declared transfer size
final class ResourceSafeguardsTests: XCTestCase {

    /// Loopback interface that records the wire context of every packet it sends,
    /// so a test can assert which control packets crossed the link.
    final class RecordingLoopback: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: RecordingLoopback?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sentContexts: [Packet.Context] = []
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            sentContexts.append(packet.context)
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    private var aT: Transport!; private var bT: Transport!
    private var aI: RecordingLoopback!; private var bI: RecordingLoopback!

    private func establishLink() throws -> (Link, Link) {
        aT = Transport(); bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["safeguards"])
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        aI = RecordingLoopback(name: "A"); bI = RecordingLoopback(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)
        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aT.onLinkEstablished = { _ in aE.fulfill() }; bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aLink, bLink)
    }

    private func sampleAdvertisement() -> ResourceAdvertisement {
        ResourceAdvertisement(
            transferSize: 1024,
            dataSize: 2048,
            partCount: 8,
            resourceHash: Data(repeating: 0xA1, count: 32),
            randomHash: Data(repeating: 0xB2, count: 32),
            originalHash: Data(repeating: 0xC3, count: 32),
            segmentIndex: 1,
            totalSegments: 1,
            requestID: nil,
            hashmap: Data(repeating: 0xD4, count: 4 * 8),
            encrypted: true,
            compressed: false,
            split: false,
            isRequest: false,
            isResponse: false,
            hasMetadata: false
        )
    }

    /// A receiver that cancels an in-progress incoming transfer must send a
    /// RESOURCE_RCL packet to the sender. Mirrors Python Resource.cancel()
    /// receiver branch (commit bb289744).
    func testReceiverCancelEmitsResourceReceiverCancel() throws {
        let (aLink, bLink) = try establishLink()

        // Register a receiver on the B side and hand it an advertisement (no sender
        // ever responds to its part requests, so it stays mid-transfer).
        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()
        try aLink.send(sampleAdvertisement().pack(), context: .resourceAdvertisement)

        // The receiver should now be transferring.
        XCTAssertEqual(receiver.status, .transferring)

        // Clear anything sent during advertisement handling, then cancel.
        bI.sentContexts.removeAll()
        receiver.cancel()

        XCTAssertTrue(bI.sentContexts.contains(.resourceReceiverCancel),
                      "receiver must emit RESOURCE_RCL on cancel; sent: \(bI.sentContexts)")
    }

    /// unpack must reject an advertisement whose declared transfer size exceeds
    /// 3× the max efficient size (Python raises ValueError). The boundary value
    /// (exactly 3×) is still accepted.
    func testAdvertisementUnpackRejectsOversizedTransfer() throws {
        let cap = ResourceTransfer.maxEfficientSize * 3   // (1 MiB − 1) × 3

        func advert(transferSize: UInt64) -> Data {
            ResourceAdvertisement(
                transferSize: transferSize,
                dataSize: 2048, partCount: 8,
                resourceHash: Data(repeating: 0xA1, count: 32),
                randomHash: Data(repeating: 0xB2, count: 32),
                originalHash: Data(repeating: 0xC3, count: 32),
                segmentIndex: 1, totalSegments: 1, requestID: nil,
                hashmap: Data(repeating: 0xD4, count: 4 * 8),
                encrypted: true, compressed: false, split: false,
                isRequest: false, isResponse: false, hasMetadata: false
            ).pack()
        }

        // At the cap: accepted.
        XCTAssertNoThrow(try ResourceAdvertisement.unpack(advert(transferSize: UInt64(cap))))
        // One over the cap: rejected.
        XCTAssertThrowsError(try ResourceAdvertisement.unpack(advert(transferSize: UInt64(cap) + 1)))
    }
}
