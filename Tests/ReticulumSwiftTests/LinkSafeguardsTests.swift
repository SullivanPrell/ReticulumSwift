import XCTest
@testable import ReticulumSwift

/// Parity tests for RNS 1.3.9 Link safeguards (commits bb289744 / 3a36c367):
/// - link-identify applied at most once (Link.py:972)
/// - teardown() idempotency (Link.py:667)
/// - link teardown on malformed resource advertisement (Link.py:1048)
final class LinkSafeguardsTests: XCTestCase {

    /// Holds every object the link depends on. `Link.transport` is a weak
    /// reference, so the Transport instances must be retained by the caller for
    /// the duration of the test — otherwise link sends fail with `.invalidState`.
    private final class LinkPair {
        let tA: Transport; let tB: Transport
        let iA: LoopbackInterface; let iB: LoopbackInterface
        let dst: Destination
        let initiator: Link
        var responder: Link?
        init(tA: Transport, tB: Transport, iA: LoopbackInterface, iB: LoopbackInterface,
             dst: Destination, initiator: Link, responder: Link?) {
            self.tA = tA; self.tB = tB; self.iA = iA; self.iB = iB
            self.dst = dst; self.initiator = initiator; self.responder = responder
        }
    }

    private func makeLinkPair() throws -> LinkPair {
        let dstIdentity = Identity()
        let dst = try Destination(
            identity: dstIdentity,
            direction: .in,
            kind: .single,
            appName: "test",
            aspects: []
        )
        let tA = Transport(); let tB = Transport()
        let iA = LoopbackInterface(name: "A"); let iB = LoopbackInterface(name: "B")
        iA.paired = iB; iB.paired = iA
        tA.register(interface: iA); tB.register(interface: iB)
        tB.register(destination: dst); tB.ownerIdentity = dstIdentity

        var responderLink: Link?
        dst.onLinkEstablished = { l in responderLink = l }

        let link = try Link.initiate(destination: dst, transport: tA)
        return LinkPair(tA: tA, tB: tB, iA: iA, iB: iB, dst: dst, initiator: link, responder: responderLink)
    }

    /// A second, validly-signed LINKIDENTIFY from a different identity must be
    /// ignored: the responder keeps the first identity and fires the callback once.
    func testRemoteIdentifyAppliedOnlyOnce() throws {
        let identityA = Identity()
        let identityB = Identity()

        let dstIdentity = Identity()
        let dst = try Destination(identity: dstIdentity, direction: .in, kind: .single, appName: "test", aspects: [])
        let tA = Transport(); let tB = Transport()
        let iA = LoopbackInterface(name: "A"); let iB = LoopbackInterface(name: "B")
        iA.paired = iB; iB.paired = iA
        tA.register(interface: iA); tB.register(interface: iB)
        tB.register(destination: dst); tB.ownerIdentity = dstIdentity

        var responderLink: Link?
        var identifyCount = 0
        dst.onLinkEstablished = { l in
            responderLink = l
            l.onRemoteIdentified = { _, _ in identifyCount += 1 }
        }

        let link = try Link.initiate(destination: dst, transport: tA)
        XCTAssertEqual(link.status, .active)

        try link.identify(as: identityA)
        Thread.sleep(forTimeInterval: 0.1)
        // Second identify with a different identity must be ignored by the responder.
        try link.identify(as: identityB)
        Thread.sleep(forTimeInterval: 0.1)

        guard let rLink = responderLink else { XCTFail("no responder link"); return }
        XCTAssertEqual(identifyCount, 1, "remote_identified must fire exactly once")
        XCTAssertEqual(rLink.remoteIdentity?.publicKeyBytes, identityA.publicKeyBytes,
                       "remote identity must stay the first identity and not be overwritten")
    }

    /// Calling teardown() twice must fire onClosed exactly once and leave the link closed.
    func testTeardownIsIdempotent() throws {
        let pair = try makeLinkPair()
        let link = pair.initiator
        XCTAssertEqual(link.status, .active)

        var closedCount = 0
        link.onClosed = { _ in closedCount += 1 }

        try link.teardown()
        XCTAssertEqual(link.status, .closed)
        try link.teardown()  // second call is a no-op
        XCTAssertEqual(link.status, .closed)
        XCTAssertEqual(closedCount, 1, "onClosed must fire exactly once across repeated teardown")
    }

    /// A malformed resource advertisement on an authenticated link (with no
    /// pre-registered receiver) tears the link down.
    func testMalformedResourceAdvertisementTearsDownLink() throws {
        let pair = try makeLinkPair()
        let link = pair.initiator
        XCTAssertEqual(link.status, .active)
        guard let rLink = pair.responder else { XCTFail("no responder link"); return }
        XCTAssertEqual(rLink.status, .active)

        // Not a valid msgpack ResourceAdvertisement dictionary.
        let garbage = Data([0xff, 0xff, 0xff, 0x00, 0x01])
        try link.send(garbage, context: .resourceAdvertisement)
        Thread.sleep(forTimeInterval: 0.15)

        XCTAssertEqual(rLink.status, .closed,
                       "responder must tear down on a malformed resource advertisement")
    }
}
