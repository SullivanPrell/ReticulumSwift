import XCTest
@testable import ReticulumSwift

/// Tests for ResourceTransfer accessor properties mirroring Python's
/// Resource.get_progress(), get_transfer_size(), get_data_size(), etc.
final class ResourceAccessorTests: XCTestCase {

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

    var aT: Transport!
    var bT: Transport!

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

    func testProgressStartsAtZero() throws {
        let (aLink, bLink) = try establishLink()
        let rt = ResourceTransfer(link: bLink)
        rt.bindAsReceiver()
        XCTAssertEqual(rt.progress, 0.0)
        _ = aLink
    }

    func testProgressAfterCompleteTransfer() throws {
        let (aLink, bLink) = try establishLink()

        let payload = Data(repeating: 0xAB, count: 200)
        let completed = expectation(description: "transfer-complete")
        var receivedData: Data?

        let sender = ResourceTransfer(link: aLink)
        sender.onComplete = { _ in completed.fulfill() }

        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()
        receiver.onPayloadReceived = { data, _ in receivedData = data }

        try sender.send(payload: payload)
        wait(for: [completed], timeout: 3.0)

        XCTAssertEqual(receivedData, payload)
        XCTAssertEqual(receiver.progress, 1.0, accuracy: 0.001)
    }

    func testTransferSizeAndDataSizeAccessors() throws {
        let (aLink, bLink) = try establishLink()

        let payload = Data(repeating: 0xCD, count: 256)
        let completed = expectation(description: "complete")

        let sender = ResourceTransfer(link: aLink)
        sender.onComplete = { _ in completed.fulfill() }
        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()

        try sender.send(payload: payload)
        wait(for: [completed], timeout: 3.0)

        XCTAssertGreaterThan(receiver.transferSize, 0, "transferSize should be populated")
        // dataSize is the logical (uncompressed) payload size; transferSize is the
        // encrypted wire size. The default BZip2Compressor shrinks this highly
        // compressible payload, so transferSize < dataSize here — the accessors are
        // independent, so assert each is populated as expected rather than ordering them.
        XCTAssertEqual(receiver.dataSize, payload.count, "dataSize should reflect the uncompressed payload")
    }

    func testHashAccessor() throws {
        let (aLink, bLink) = try establishLink()

        let payload = Data(repeating: 0xEF, count: 128)
        let completed = expectation(description: "complete")
        let sender = ResourceTransfer(link: aLink)
        sender.onComplete = { _ in completed.fulfill() }
        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()

        try sender.send(payload: payload)
        wait(for: [completed], timeout: 3.0)

        XCTAssertFalse(receiver.hash.isEmpty)
        XCTAssertEqual(receiver.hash.count, Constants.hashLength)
        XCTAssertEqual(sender.hash.count, Constants.hashLength)
        XCTAssertEqual(sender.hash, receiver.hash)
    }

    func testPartCountAccessor() throws {
        let (aLink, bLink) = try establishLink()

        let payload = Data(repeating: 0xFF, count: 100)
        let completed = expectation(description: "complete")
        let sender = ResourceTransfer(link: aLink)
        sender.onComplete = { _ in completed.fulfill() }
        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()

        try sender.send(payload: payload)
        wait(for: [completed], timeout: 3.0)

        XCTAssertGreaterThan(receiver.partCount, 0)
        XCTAssertEqual(receiver.segmentCount, 1)
    }
}
