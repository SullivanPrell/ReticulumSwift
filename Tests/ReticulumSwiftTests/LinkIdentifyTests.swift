import XCTest
@testable import ReticulumSwift

final class LinkIdentifyTests: XCTestCase {

    func testInitiatorCanIdentifyToResponder() throws {
        let srcIdentity = Identity()
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
        
        

        let linkEstablished = expectation(description: "link established")
        let identified = expectation(description: "remote identified")
        var identifiedIdentity: Identity?

        // Must set destination callback BEFORE initiating — loopback is synchronous.
        dst.onLinkEstablished = { responderLink in
            responderLink.onRemoteIdentified = { _, identity in
                identifiedIdentity = identity
                identified.fulfill()
            }
        }

        let link = try Link.initiate(destination: dst, transport: tA)
        link.onEstablished = { l in
            linkEstablished.fulfill()
            try? l.identify(as: srcIdentity)
        }

        wait(for: [linkEstablished, identified], timeout: 2)
        XCTAssertNotNil(identifiedIdentity)
        XCTAssertEqual(identifiedIdentity?.publicKeyBytes, srcIdentity.publicKeyBytes)
    }

    func testIdentifyOnlyWorksForInitiator() throws {
        let dstIdentity = Identity()
        let dst = try Destination(
            identity: dstIdentity,
            direction: .in,
            kind: .single,
            appName: "test",
            aspects: []
        )
        let tA = Transport()
        let iA = LoopbackInterface(name: "A"); let iB = LoopbackInterface(name: "B")
        iA.paired = iB; iB.paired = iA
        let tB = Transport()
        tA.register(interface: iA); tB.register(interface: iB)
        tB.register(destination: dst); tB.ownerIdentity = dstIdentity
        
        

        var responderLink: Link?
        dst.onLinkEstablished = { l in responderLink = l }

        let link = try Link.initiate(destination: dst, transport: tA)
        var initiatorEstablished = false
        link.onEstablished = { _ in initiatorEstablished = true }

        // Wait a tick for synchronous loopback to complete.
        XCTAssertTrue(initiatorEstablished || link.status == .active)

        // Responder should throw if it tries to identify.
        if let rLink = responderLink {
            XCTAssertThrowsError(try rLink.identify(as: dstIdentity))
        }
    }

    func testIdentifySignatureVerification() throws {
        // Tampered identify packet should not set remoteIdentity.
        let srcIdentity = Identity()
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
        // With synchronous loopback, link is established immediately.

        // Manually send a tampered LINKIDENTIFY packet (wrong pubkey / invalid sig).
        guard let rLink = responderLink else { XCTFail("no responder link"); return }
        let tampered = srcIdentity.publicKeyBytes + Data(count: 64)  // zero signature
        try? link.send(tampered, context: .linkIdentify)

        // Give it a moment to process.
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertNil(rLink.remoteIdentity)
    }
}
