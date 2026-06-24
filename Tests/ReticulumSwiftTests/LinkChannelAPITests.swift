import XCTest
@testable import ReticulumSwift

/// Tests for Link.get_channel() API (mirrors Python's Link.get_channel()).
final class LinkChannelAPITests: XCTestCase {

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
                                    appName: "test", aspects: ["channel"])
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

    // MARK: - get_channel() idempotency

    func testGetChannelReturnsSameObject() throws {
        let (aLink, _) = try establishLink()
        let ch1 = aLink.getChannel()
        let ch2 = aLink.getChannel()
        XCTAssertTrue(ch1 === ch2, "getChannel() must return the same channel object on repeated calls")
    }

    func testChannelMDUIsLinkMDUMinusHeader() throws {
        let (aLink, _) = try establishLink()
        let channel = aLink.getChannel()
        // Channel MDU = link MDU (431) - 6-byte envelope header = 425
        XCTAssertEqual(channel.mdu, Constants.linkMdu - 6)
    }

    func testChannelIsReadyToSendWhenLinkActive() throws {
        let (aLink, _) = try establishLink()
        XCTAssertTrue(aLink.getChannel().isReadyToSend())
    }

    // MARK: - Channel message round-trip

    final class TestMessage: MessageBase {
        override class var typeID: UInt16 { 0x1001 }
        var payload: Data = Data()

        override func pack() throws -> Data { payload }
        override func unpack(_ data: Data) throws { payload = data }
    }

    func testChannelSendAndReceive() throws {
        let (aLink, bLink) = try establishLink()
        let aCh = aLink.getChannel()
        let bCh = bLink.getChannel()

        try aCh.registerMessageType(TestMessage.self)
        try bCh.registerMessageType(TestMessage.self)

        let received = expectation(description: "received")
        var receivedMsg: TestMessage?
        bCh.addMessageHandler { msg in
            receivedMsg = msg as? TestMessage
            received.fulfill()
            return true
        }

        let msg = TestMessage()
        msg.payload = Data("hello channel".utf8)
        try aCh.send(msg)
        wait(for: [received], timeout: 1.0)

        XCTAssertEqual(receivedMsg?.payload, Data("hello channel".utf8))
    }
}
