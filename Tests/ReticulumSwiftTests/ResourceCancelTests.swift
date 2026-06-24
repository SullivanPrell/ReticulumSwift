import XCTest
@testable import ReticulumSwift

/// Tests for Resource cancel behavior mirroring Python's Resource.cancel().
final class ResourceCancelTests: XCTestCase {

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
                                    appName: "test", aspects: ["cancel"])
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

    func testSenderCanCancelResource() throws {
        let (aLink, bLink) = try establishLink()
        let payload = Data(repeating: 0xAA, count: 100)

        let failed = expectation(description: "failed")
        let sender = ResourceTransfer(link: aLink)
        sender.onFailed = { _, _ in failed.fulfill() }

        // Register a receiver that won't immediately complete
        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()

        try sender.send(payload: payload)
        sender.cancel()
        wait(for: [failed], timeout: 1.0)

        XCTAssertTrue(sender.status.isTerminal, "sender should be in terminal state after cancel")
    }

    func testCancelSetsFailedStatus() throws {
        let (aLink, _) = try establishLink()
        let payload = Data(repeating: 0xBB, count: 100)
        let sender = ResourceTransfer(link: aLink)
        try sender.send(payload: payload)
        sender.cancel()

        if case .failed = sender.status { } else {
            XCTFail("status should be .failed after cancel, got \(sender.status)")
        }
    }
}
