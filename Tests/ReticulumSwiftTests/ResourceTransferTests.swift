import XCTest
@testable import ReticulumSwift

final class ResourceTransferTests: XCTestCase {

    /// Bidirectional in-memory loopback interface pair backed by two Transport instances.
    final class LoopbackInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
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

    func wire(_ a: LoopbackInterface, _ b: LoopbackInterface) {
        a.paired = b; b.paired = a
    }

    // Sets up two transports, a link, and returns (aLink, bLink).
    func makeLinkedPair() throws -> (aTransport: Transport, bTransport: Transport, aLink: Link, bLink: Link) {
        let aTransport = Transport()
        let bTransport = Transport()

        let bIdentity = Identity()
        let bDestination = try Destination(
            identity: bIdentity, direction: .in, kind: .single, appName: "test"
        )
        bTransport.ownerIdentity = bIdentity
        bTransport.register(destination: bDestination)

        let aIface = LoopbackInterface(name: "A→B")
        let bIface = LoopbackInterface(name: "B→A")
        wire(aIface, bIface)
        aTransport.register(interface: aIface)
        bTransport.register(interface: bIface)

        let aE = expectation(description: "A established")
        let bE = expectation(description: "B established")
        aTransport.onLinkEstablished = { _ in aE.fulfill() }
        bTransport.onLinkEstablished = { _ in bE.fulfill() }

        let aLink = try Link.initiate(destination: bDestination, transport: aTransport)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bTransport.links[aLink.linkID!])
        return (aTransport, bTransport, aLink, bLink)
    }

    // MARK: - Tests

    func testResourceRoundTripSingleSegment() throws {
        let (aT, bT, aLink, bLink) = try makeLinkedPair()
        _ = (aT, bT)

        let receivedPayload = expectation(description: "B got payload")
        let senderComplete = expectation(description: "A got proof")
        var got: Data?

        // Receiver binds first.
        let bRx = ResourceTransfer(link: bLink)
        bRx.bindAsReceiver()
        bRx.onPayloadReceived = { data, _ in got = data; receivedPayload.fulfill() }

        let aTx = ResourceTransfer(link: aLink)
        aTx.onComplete = { _ in senderComplete.fulfill() }

        let payload = Data(repeating: 0xAA, count: 200)
        try aTx.send(payload: payload)

        wait(for: [receivedPayload, senderComplete], timeout: 2.0)
        XCTAssertEqual(got, payload)
        XCTAssertEqual(aTx.status, .complete)
        XCTAssertEqual(bRx.status, .complete)
    }

    func testResourceRoundTripMultiSegment() throws {
        let (aT, bT, aLink, bLink) = try makeLinkedPair()
        _ = (aT, bT)

        let bRx = ResourceTransfer(link: bLink)
        bRx.bindAsReceiver()
        let aTx = ResourceTransfer(link: aLink)

        var got: Data?
        let received = expectation(description: "payload")
        let complete = expectation(description: "complete")
        bRx.onPayloadReceived = { d, _ in got = d; received.fulfill() }
        aTx.onComplete = { _ in complete.fulfill() }

        // 150 bytes at 50-byte segments = 3 segments.
        var payload = Data()
        for i: UInt8 in 0 ..< 150 { payload.append(i) }
        try aTx.send(payload: payload, segmentSize: 50)

        wait(for: [received, complete], timeout: 2.0)
        XCTAssertEqual(got, payload)
        // Part count reflects the encrypted stream size (plaintext + random hash +
        // Token overhead), not just the raw payload size.
        XCTAssertGreaterThan(aTx.advertisement?.partCount ?? 0, 1)
    }

    func testResourceHashWireFormat() throws {
        let (aT, bT, aLink, _) = try makeLinkedPair()
        _ = (aT, bT)

        // Verify hash computation matches Python: sha256(plaintext + randomHash).
        let payload = Data("hello resource".utf8)
        let resource = try Resource(link: aLink, payload: payload, segmentSize: 500)

        // resource.resourceHash should be sha256(payload + randomHash) — 32 bytes.
        XCTAssertEqual(resource.resourceHash.count, 32)
        let expected = Hashes.fullHash(payload + resource.randomHash)
        XCTAssertEqual(resource.resourceHash, expected)

        // randomHash should be 4 bytes.
        XCTAssertEqual(resource.randomHash.count, Resource.randomHashSize)
        XCTAssertEqual(Resource.randomHashSize, 4)

        // Map hashes should be 4 bytes each.
        for mh in resource.mapHashes {
            XCTAssertEqual(mh.count, Resource.mapHashLength)
        }
    }

    func testResourceAcceptAllStrategy() throws {
        let (aT, bT, aLink, bLink) = try makeLinkedPair()
        _ = (aT, bT)

        let received = expectation(description: "resource concluded")
        let complete = expectation(description: "sender complete")
        var gotPayload: Data?

        // Configure bLink to accept all incoming resources.
        bLink.resourceStrategy = .acceptAll
        bLink.onResourceConcluded = { payload, _, _ in
            gotPayload = payload
            received.fulfill()
        }

        let aTx = ResourceTransfer(link: aLink)
        aTx.onComplete = { _ in complete.fulfill() }

        let payload = Data(repeating: 0xBB, count: 200)
        try aTx.send(payload: payload)

        wait(for: [received, complete], timeout: 2.0)
        XCTAssertEqual(gotPayload, payload)
    }

    // MARK: - Metadata tests

    func testResourceMetadataFlagSetInAdvertisement() throws {
        let (_, _, aLink, _) = try makeLinkedPair()
        let payload = Data("hello".utf8)
        let meta = Data([0x01, 0x02, 0x03])  // 3 bytes pre-packed metadata
        let resource = try Resource(link: aLink, payload: payload, metadata: meta)
        XCTAssertTrue(resource.hasMetadata)
    }

    func testResourceWithoutMetadataFlagNotSet() throws {
        let (_, _, aLink, _) = try makeLinkedPair()
        let resource = try Resource(link: aLink, payload: Data("hello".utf8))
        XCTAssertFalse(resource.hasMetadata)
    }

    func testResourceMetadataRoundTripOverLink() throws {
        let (aT, bT, aLink, bLink) = try makeLinkedPair()
        _ = (aT, bT)

        let meta = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let payload = Data("resource payload".utf8)

        let senderTransfer = ResourceTransfer(link: aLink)
        let receiverTransfer = ResourceTransfer(link: bLink)
        receiverTransfer.bindAsReceiver()

        let receivedPayload = expectation(description: "payload received")
        let senderComplete = expectation(description: "sender complete")
        var gotPayload: Data?
        var gotMeta: Data?
        receiverTransfer.onPayloadReceived = { data, transfer in
            gotPayload = data
            gotMeta = transfer.receivedMetadata
            receivedPayload.fulfill()
        }
        // Verify proof validation succeeds (sender's onComplete fires).
        senderTransfer.onComplete = { _ in senderComplete.fulfill() }
        bLink.registerIncomingResource(receiverTransfer)

        try senderTransfer.send(payload: payload, metadata: meta)

        wait(for: [receivedPayload, senderComplete], timeout: 2.0)
        XCTAssertEqual(gotPayload, payload)
        XCTAssertEqual(gotMeta, meta)
    }

    func testResourceMetadataTooLargeThrows() throws {
        let (_, _, aLink, _) = try makeLinkedPair()
        let oversized = Data(repeating: 0xFF, count: Resource.metadataMaxSize + 1)
        XCTAssertThrowsError(try Resource(link: aLink, payload: Data("x".utf8), metadata: oversized)) { error in
            XCTAssertEqual(error as? ResourceError, .metadataTooLarge)
        }
    }

    func testResourceAssemblyWithMetadata() throws {
        let (_, _, aLink, bLink) = try makeLinkedPair()

        let meta = Data([0xCA, 0xFE])
        let payload = Data("body".utf8)
        let resource = try Resource(link: aLink, payload: payload, metadata: meta)

        // Verify the advertisement has hasMetadata=true.
        XCTAssertTrue(resource.hasMetadata)

        // Manually assemble using the receiver-side link.
        let result = Resource.assemble(
            encryptedParts: resource.encryptedSegments,
            randomHash: resource.randomHash,
            resourceHash: resource.resourceHash,
            compressed: resource.isCompressed,
            hasMetadata: true,
            link: bLink
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.payload, payload)
        XCTAssertEqual(result?.metadata, meta)
    }

    func testResourceAssemblyWithoutMetadataBackwardsCompatible() throws {
        let (_, _, aLink, bLink) = try makeLinkedPair()

        let payload = Data("no meta".utf8)
        let resource = try Resource(link: aLink, payload: payload)

        let result = Resource.assemble(
            encryptedParts: resource.encryptedSegments,
            randomHash: resource.randomHash,
            resourceHash: resource.resourceHash,
            compressed: resource.isCompressed,
            link: bLink
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.payload, payload)
        XCTAssertNil(result?.metadata)
    }

    func testResourceAdvertisementRoundTrip() throws {
        let (aT, bT, aLink, _) = try makeLinkedPair()
        _ = (aT, bT)
        let payload = Data(repeating: 0xBB, count: 300)
        let resource = try Resource(link: aLink, payload: payload, segmentSize: 100)

        let adv = ResourceAdvertisement(
            transferSize: UInt64(resource.transferSize),
            dataSize: UInt64(resource.dataSize),
            partCount: UInt64(resource.partCount),
            resourceHash: resource.resourceHash,
            randomHash: resource.randomHash,
            originalHash: resource.resourceHash,
            segmentIndex: 1,
            totalSegments: 1,
            requestID: nil,
            hashmap: resource.mapHashes.reduce(Data(), +),
            encrypted: true,
            compressed: resource.isCompressed,
            split: false
        )
        let decoded = try ResourceAdvertisement.unpack(adv.pack())
        XCTAssertEqual(decoded.resourceHash, resource.resourceHash)
        XCTAssertEqual(decoded.randomHash, resource.randomHash)
        XCTAssertEqual(decoded.partCount, UInt64(resource.partCount))
        XCTAssertEqual(decoded.hashmap, resource.mapHashes.reduce(Data(), +))
    }
}
