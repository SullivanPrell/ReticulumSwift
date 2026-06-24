import XCTest
@testable import ReticulumSwift

/// Tests for resource metadata handling (mirrors Python's Resource metadata tests).
final class ResourceMetadataTests: XCTestCase {

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
                                    appName: "test", aspects: ["meta"])
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

    // MARK: - Metadata size limit

    func testOversizedMetadataThrows() throws {
        let (aLink, _) = try establishLink()
        let oversized = Data(repeating: 0xFF, count: Resource.metadataMaxSize + 1)
        XCTAssertThrowsError(try Resource(link: aLink, payload: Data("data".utf8), metadata: oversized)) { error in
            XCTAssertTrue(error is ResourceError, "should throw ResourceError.metadataTooLarge")
        }
    }

    func testMetadataMaxSizeConstant() {
        // Python: Resource.METADATA_MAX_SIZE = 16777215 = 2^24 - 1
        XCTAssertEqual(Resource.metadataMaxSize, 16_777_215)
    }

    func testValidMetadataSizeAccepted() throws {
        let (aLink, _) = try establishLink()
        let valid = Data(repeating: 0xAA, count: 100)
        XCTAssertNoThrow(try Resource(link: aLink, payload: Data("test".utf8), metadata: valid))
    }

    // MARK: - Metadata round-trip

    func testMetadataRoundTrip() throws {
        let (aLink, bLink) = try establishLink()
        let payload = Data("payload data".utf8)
        let metadata = Data("metadata bytes".utf8)

        let done = expectation(description: "complete")
        var receivedPayload: Data?
        var receivedMetadata: Data?

        let sender = ResourceTransfer(link: aLink)
        sender.onComplete = { _ in done.fulfill() }

        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()
        receiver.onPayloadReceived = { data, rt in
            receivedPayload = data
            receivedMetadata = rt.receivedMetadata
        }

        try sender.send(payload: payload, metadata: metadata)
        wait(for: [done], timeout: 3.0)

        XCTAssertEqual(receivedPayload, payload)
        XCTAssertEqual(receivedMetadata, metadata, "metadata should survive round-trip")
    }

    func testNoMetadataRoundTrip() throws {
        let (aLink, bLink) = try establishLink()
        let payload = Data("just payload".utf8)

        let done = expectation(description: "complete")
        var receivedMetadata: Data? = Data("not nil".utf8)  // non-nil to detect if it changes

        let sender = ResourceTransfer(link: aLink)
        sender.onComplete = { _ in done.fulfill() }

        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()
        receiver.onPayloadReceived = { _, rt in receivedMetadata = rt.receivedMetadata }

        try sender.send(payload: payload)  // no metadata
        wait(for: [done], timeout: 3.0)

        XCTAssertNil(receivedMetadata, "no metadata should result in nil receivedMetadata")
    }
}
