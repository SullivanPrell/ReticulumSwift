import XCTest
@testable import ReticulumSwift

/// A request response larger than the link MDU must arrive — `bugs/033`.
///
/// Found by the rebuilt `tri-test` large-page cell: a Swift NomadNet host accepts the link,
/// logs the request, and sends nothing for any page needing more than one resource part. The
/// fetcher waits out its timeout. A small page over the same link, in the same session, is
/// served correctly, so the break is size-dependent.
///
/// NomadNet page serving is an ordinary link request whose response is resourced when it
/// exceeds the MDU (`LinkRequest.swift:515-521`, mirroring `Link.py:848-852`), so the defect
/// is reproduced here at the layer it actually lives in rather than through three processes
/// and a 64 KB Micron page.
///
/// **Why nothing caught it.** Every existing request/response test fits its response in one
/// packet, and the resource tests drive `ResourceTransfer` directly rather than through
/// `handleRequest`'s over-MDU branch. That branch calls `try? rt.send(...)`, so anything it
/// throws is discarded silently — which is exactly what "logs the request and sends nothing"
/// looks like from outside.
final class LargeRequestResponseTests: XCTestCase {

    private final class LoopbackPairInterface: Interface {
        var name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        weak var paired: LoopbackPairInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            // `pack()`, deliberately — because that is what every real interface does
            // (`TCPClientInterface.swift:129`, `TCPServerInterface.swift:163`, and eleven
            // others). Using `packedBytes()` here would make the stub more permissive than any
            // medium the port actually ships, and would hide `bugs/033` exactly the way the
            // absence of this test hid it.
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    /// Deterministic incompressible bytes, so a size assertion cannot be defeated by the
    /// compressor — the mechanism that made `tri-test`'s large-page cell unfalsifiable for the
    /// whole life of `bugs/016`.
    private func incompressible(_ count: Int) -> Data {
        var out = Data()
        var block = Data("bugs-033".utf8)
        while out.count < count {
            block = Hashes.fullHash(block)
            out.append(block)
        }
        return out.prefix(count)
    }

    private func establishedPair(aspect: String) throws -> (Link, Destination, Transport, Transport) {
        let aT = Transport(), bT = Transport()
        let bID = Identity()
        let bDest = try Destination(identity: bID, direction: .in, kind: .single,
                                    appName: "test", aspects: [aspect])
        bT.ownerIdentity = bID
        bT.register(destination: bDest)

        let aI = LoopbackPairInterface(name: "A"), bI = LoopbackPairInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)

        // Wait for BOTH sides: the responder must have its Link before a request arrives,
        // or the request lands on a half-built session and no response is ever produced.
        let aUp = expectation(description: "initiator link established")
        let bUp = expectation(description: "responder link established")
        aT.onLinkEstablished = { _ in aUp.fulfill() }
        bT.onLinkEstablished = { _ in bUp.fulfill() }
        let link = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aUp, bUp], timeout: 2.0)
        XCTAssertEqual(link.status, .active)
        return (link, bDest, aT, bT)
    }

    /// The direct analogue of fetching a NomadNet page bigger than one part.
    func testAResponseLargerThanTheMDUIsDelivered() throws {
        // Both transports must stay alive for the whole test: `Link.transport` is a weak
        // reference, so discarding them here makes every send throw `invalidState`.
        let (link, bDest, aT, bT) = try establishedPair(aspect: "large-response")
        defer { withExtendedLifetime((aT, bT)) {} }

        // Comfortably over the base MDU, and over one resource part, so the response has to
        // travel as a multi-part resource.
        let page = incompressible(64 * 1024)
        // `allow: .all` — the default is `.none`, which refuses every request.
        bDest.registerRequestHandler(path: "/page/large.mu", allow: .all) { _, _, _, _, _ in page }

        let got = expectation(description: "response received")
        var received: Data?
        let receipt = try link.request(path: "/page/large.mu", data: nil,
                                       responseCallback: { response, _ in
            received = response
            got.fulfill()
        })
        _ = receipt

        wait(for: [got], timeout: 20.0)
        XCTAssertEqual(received?.count, page.count,
                       "the response arrived truncated or empty")
        XCTAssertEqual(received, page,
                       "the response arrived but its bytes differ from what was served")
    }

    /// The same thing over a link whose MTU was raised, which is the case the interop suite
    /// actually runs.
    ///
    /// `bugs/016` sized resource parts from the negotiated per-link MTU on both sides, so a
    /// response over an upgraded link is segmented completely differently from one over a base
    /// link: 5 parts at an 8120-byte sdu rather than ~142 at 464. The test above exercises only
    /// the base-MTU path — which passes — so it cannot see a defect that needs the upgraded one.
    func testAResponseLargerThanTheMDUIsDeliveredOverAnUpgradedLink() throws {
        let (link, bDest, aT, bT) = try establishedPair(aspect: "large-response-high-mtu")
        defer { withExtendedLifetime((aT, bT)) {} }

        // Both ends, together: a link MTU is a property of the link, and moving one side alone
        // *is* the bug/016 defect rather than a way to test around it.
        let responderLink = try XCTUnwrap(bT.links[link.linkID!])
        link.establishedMtu = 8192
        responderLink.establishedMtu = 8192

        let page = incompressible(64 * 1024)
        bDest.registerRequestHandler(path: "/page/large.mu", allow: .all) { _, _, _, _, _ in page }

        let got = expectation(description: "response received")
        var received: Data?
        _ = try link.request(path: "/page/large.mu", data: nil,
                             responseCallback: { response, _ in
            received = response
            got.fulfill()
        })

        wait(for: [got], timeout: 20.0)
        XCTAssertEqual(received?.count, page.count,
                       "the response never arrived over an upgraded link, though the same "
                       + "response arrives over a base-MTU link")
        XCTAssertEqual(received, page)
    }

    /// The control: the same path, a response that fits in one packet. If this fails too, the
    /// defect is not size-dependent and the test above is measuring something else.
    func testASmallResponseIsDelivered() throws {
        let (link, bDest, aT, bT) = try establishedPair(aspect: "small-response")
        defer { withExtendedLifetime((aT, bT)) {} }

        let page = Data("# index\nsmall enough for one packet".utf8)
        bDest.registerRequestHandler(path: "/page/index.mu", allow: .all) { _, _, _, _, _ in page }

        let got = expectation(description: "response received")
        var received: Data?
        _ = try link.request(path: "/page/index.mu", data: nil,
                             responseCallback: { response, _ in
            received = response
            got.fulfill()
        })
        wait(for: [got], timeout: 10.0)
        XCTAssertEqual(received, page)
    }
}
