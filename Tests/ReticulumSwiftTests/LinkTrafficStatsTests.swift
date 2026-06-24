import XCTest
@testable import ReticulumSwift

/// Tests for Link traffic statistics mirroring Python's Link.tx, .rx, .txbytes, .rxbytes.
final class LinkTrafficStatsTests: XCTestCase {

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

    var aT: Transport!; var bT: Transport!

    private func establishLink() throws -> (Link, Link) {
        aT = Transport(); bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["stats"])
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

    // MARK: - Tx/Rx packet counts

    func testTxCountIncreasesOnSend() throws {
        let (aLink, bLink) = try establishLink()
        let before = aLink.tx
        let received = expectation(description: "rx")
        bLink.onDataReceived = { _, _ in received.fulfill() }
        try aLink.send(Data("hello".utf8))
        wait(for: [received], timeout: 1.0)
        XCTAssertEqual(aLink.tx, before + 1)
    }

    func testRxCountIncreasesOnReceive() throws {
        let (aLink, bLink) = try establishLink()
        let before = bLink.rx
        let received = expectation(description: "rx")
        bLink.onDataReceived = { _, _ in received.fulfill() }
        try aLink.send(Data("hello".utf8))
        wait(for: [received], timeout: 1.0)
        XCTAssertEqual(bLink.rx, before + 1)
    }

    // MARK: - Tx/Rx byte counts

    func testTxBytesIncreasesOnSend() throws {
        let (aLink, bLink) = try establishLink()
        let before = aLink.txBytes
        let received = expectation(description: "rx")
        bLink.onDataReceived = { _, _ in received.fulfill() }
        let payload = Data("hello world".utf8)
        try aLink.send(payload)
        wait(for: [received], timeout: 1.0)
        XCTAssertGreaterThan(aLink.txBytes, before)
    }

    func testRxBytesIncreasesOnReceive() throws {
        let (aLink, bLink) = try establishLink()
        let before = bLink.rxBytes
        let received = expectation(description: "rx")
        bLink.onDataReceived = { _, _ in received.fulfill() }
        try aLink.send(Data("hello".utf8))
        wait(for: [received], timeout: 1.0)
        XCTAssertGreaterThan(bLink.rxBytes, before)
    }

    // MARK: - ACCEPT_* class constants (Python parity)

    func testAcceptNoneConstant() {
        XCTAssertEqual(Link.ResourceStrategy.acceptNone.rawValue, 0)
    }

    func testAcceptAppConstant() {
        XCTAssertEqual(Link.ResourceStrategy.acceptApp.rawValue, 1)
    }

    func testAcceptAllConstant() {
        XCTAssertEqual(Link.ResourceStrategy.acceptAll.rawValue, 2)
    }
}
