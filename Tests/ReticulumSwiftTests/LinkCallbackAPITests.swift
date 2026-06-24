import XCTest
@testable import ReticulumSwift

/// Tests for Link callback setter API mirroring Python's:
///   - `Link.set_link_closed_callback()`
///   - `Link.set_packet_callback()`
///   - `Link.set_resource_callback()`
///   - `Link.set_resource_started_callback()`
///   - `Link.set_resource_concluded_callback()`
///   - `Link.set_remote_identified_callback()`
///   - `Link.set_resource_strategy()`
final class LinkCallbackAPITests: XCTestCase {

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
                                    appName: "test", aspects: ["callbacks"])
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

    // MARK: - set_link_closed_callback

    func testSetLinkClosedCallback() throws {
        let (aLink, bLink) = try establishLink()
        let closed = expectation(description: "closed")
        aLink.setLinkClosedCallback { _ in closed.fulfill() }
        try aLink.teardown()
        wait(for: [closed], timeout: 1.0)
        _ = bLink
    }

    // MARK: - set_packet_callback

    func testSetPacketCallback() throws {
        let (aLink, bLink) = try establishLink()
        let received = expectation(description: "packet")
        aLink.setPacketCallback { _, _ in received.fulfill() }
        try bLink.send(Data("test".utf8))
        wait(for: [received], timeout: 1.0)
    }

    // MARK: - set_resource_strategy / ACCEPT_* constants

    func testResourceStrategyDefaultAcceptNone() throws {
        let (aLink, _) = try establishLink()
        XCTAssertEqual(aLink.resourceStrategy, .acceptNone)
    }

    func testSetResourceStrategyAcceptAll() throws {
        let (aLink, _) = try establishLink()
        aLink.setResourceStrategy(.acceptAll)
        XCTAssertEqual(aLink.resourceStrategy, .acceptAll)
    }

    func testResourceStrategyConstants() {
        XCTAssertEqual(Link.ResourceStrategy.acceptNone.rawValue, 0)
        XCTAssertEqual(Link.ResourceStrategy.acceptApp.rawValue, 1)
        XCTAssertEqual(Link.ResourceStrategy.acceptAll.rawValue, 2)
    }

    // MARK: - set_resource_started_callback

    func testSetResourceStartedCallback() throws {
        let (aLink, bLink) = try establishLink()
        let started = expectation(description: "resource-started")
        bLink.setResourceStrategy(.acceptAll)
        bLink.setResourceStartedCallback { _ in started.fulfill() }

        let rt = ResourceTransfer(link: aLink)
        try rt.send(payload: Data(repeating: 0xAA, count: 100))
        wait(for: [started], timeout: 2.0)
    }

    // MARK: - set_resource_concluded_callback

    func testSetResourceConcludedCallback() throws {
        let (aLink, bLink) = try establishLink()
        let concluded = expectation(description: "resource-concluded")
        // Use acceptAll strategy — bLink will auto-receive and fire onResourceConcluded
        bLink.setResourceStrategy(.acceptAll)
        bLink.setResourceConcludedCallback { _, _, _ in concluded.fulfill() }

        let sender = ResourceTransfer(link: aLink)
        let done = expectation(description: "sender-done")
        sender.onComplete = { _ in done.fulfill() }
        try sender.send(payload: Data(repeating: 0xBB, count: 100))
        wait(for: [concluded, done], timeout: 3.0)
    }

    // MARK: - set_remote_identified_callback

    func testSetRemoteIdentifiedCallback() throws {
        let (aLink, bLink) = try establishLink()
        let identified = expectation(description: "identified")
        bLink.setRemoteIdentifiedCallback { _, _ in identified.fulfill() }
        let aId = Identity()
        try aLink.identify(as: aId)
        wait(for: [identified], timeout: 1.0)
    }
}
