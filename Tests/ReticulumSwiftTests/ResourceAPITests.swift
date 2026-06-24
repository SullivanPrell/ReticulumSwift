import XCTest
@testable import ReticulumSwift

/// Tests for Resource API completeness.
final class ResourceAPITests: XCTestCase {

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
                                    appName: "test", aspects: ["resource"])
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

    // MARK: - ResourceTransfer API completeness

    func testResourceTransferHasAllRequiredProperties() throws {
        let (aLink, _) = try establishLink()
        let rt = ResourceTransfer(link: aLink)

        // Verify all API properties exist and are accessible
        XCTAssertFalse(rt.status.isTerminal)
        XCTAssertEqual(rt.progress, 0.0)
        XCTAssertEqual(rt.transferSize, 0)
        XCTAssertEqual(rt.dataSize, 0)
        XCTAssertEqual(rt.partCount, 0)
        XCTAssertEqual(rt.segmentCount, 1)  // default single segment
        XCTAssertTrue(rt.hash.isEmpty)
        XCTAssertFalse(rt.isCompressed)
    }

    func testResourceTransferStatusValues() {
        // Verify all Status cases exist
        let statuses: [ResourceTransfer.Status] = [
            .idle, .advertised, .transferring, .awaitingProof, .complete,
            .failed(reason: "test"), .rejected
        ]
        for s in statuses {
            XCTAssertNotNil(s)
        }
    }

    // MARK: - Resource.ResourceAdvertisement

    func testResourceAdvertisementFlagBits() {
        var adv = ResourceAdvertisement(
            transferSize: 100, dataSize: 100, partCount: 1,
            resourceHash: Data(repeating: 0, count: 32),
            randomHash: Data(repeating: 0, count: 4),
            originalHash: Data(repeating: 0, count: 32),
            segmentIndex: 1, totalSegments: 1,
            encrypted: true, compressed: false, split: false,
            isRequest: true, isResponse: false, hasMetadata: false
        )
        XCTAssertTrue(adv.isRequest)
        XCTAssertFalse(adv.isResponse)
        XCTAssertTrue(adv.encrypted)
        XCTAssertFalse(adv.compressed)
        XCTAssertEqual(adv.flags & 0x08, 0x08, "isRequest flag should be bit 3")

        adv.isResponse = true
        XCTAssertEqual(adv.flags & 0x10, 0x10, "isResponse flag should be bit 4")
    }

    func testResourceAdvertisementPackUnpack() throws {
        let adv = ResourceAdvertisement(
            transferSize: 512, dataSize: 256, partCount: 4,
            resourceHash: Data(repeating: 0xAA, count: 32),
            randomHash: Data(repeating: 0xBB, count: 4),
            originalHash: Data(repeating: 0xCC, count: 32),
            segmentIndex: 1, totalSegments: 2,
            requestID: Data(repeating: 0xDD, count: 16),
            hashmap: Data(repeating: 0xEE, count: 16),
            encrypted: true, compressed: true, split: true,
            isRequest: false, isResponse: true, hasMetadata: false
        )
        let packed = adv.pack()
        let unpacked = try ResourceAdvertisement.unpack(packed)

        XCTAssertEqual(unpacked.transferSize, 512)
        XCTAssertEqual(unpacked.dataSize, 256)
        XCTAssertEqual(unpacked.partCount, 4)
        XCTAssertEqual(unpacked.resourceHash, Data(repeating: 0xAA, count: 32))
        XCTAssertTrue(unpacked.compressed)
        XCTAssertTrue(unpacked.isResponse)
        XCTAssertEqual(unpacked.requestID, Data(repeating: 0xDD, count: 16))
    }

    // MARK: - Resource constants

    func testResourceConstants() {
        XCTAssertEqual(Resource.randomHashSize, 4)
        XCTAssertEqual(Resource.mapHashLength, 4)
        XCTAssertEqual(Resource.autoCompressMaxSize, 64 * 1024 * 1024)
        XCTAssertEqual(Resource.metadataMaxSize, 16_777_215)
        XCTAssertEqual(ResourceTransfer.maxEfficientSize, 1024 * 1024 - 1)
    }
}
