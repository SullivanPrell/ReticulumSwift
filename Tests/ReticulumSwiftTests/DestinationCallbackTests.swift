import XCTest
@testable import ReticulumSwift

final class DestinationCallbackTests: XCTestCase {

    private func makePairedTransports() -> (Transport, Transport, LoopbackInterface, LoopbackInterface) {
        let tA = Transport(); let tB = Transport()
        let iA = LoopbackInterface(name: "A"); let iB = LoopbackInterface(name: "B")
        iA.paired = iB; iB.paired = iA
        tA.register(interface: iA); tB.register(interface: iB)
        return (tA, tB, iA, iB)
    }

    func testOnLinkEstablishedFiresOnDestination() throws {
        let dstIdentity = Identity()
        let dst = try Destination(
            identity: dstIdentity,
            direction: .in,
            kind: .single,
            appName: "test",
            aspects: []
        )
        let (tA, tB, _, _) = makePairedTransports()
        tB.register(destination: dst)
        tB.ownerIdentity = dstIdentity

        let estab = XCTestExpectation(description: "destination callback fired")
        dst.onLinkEstablished = { _ in estab.fulfill() }

        let link = try Link.initiate(destination: dst, transport: tA)
        link.onEstablished = { _ in }

        wait(for: [estab], timeout: 2)
    }

    func testProofStrategyIsProveNoneByDefault() throws {
        // Python default: Destination.PROVE_NONE — don't auto-prove DATA packets.
        let identity = Identity()
        let dst = try Destination(identity: identity, direction: .in, kind: .single, appName: "t", aspects: [])
        XCTAssertEqual(dst.proofStrategy, .proveNone)
    }

    func testProofStrategyCanBeChanged() throws {
        let identity = Identity()
        let dst = try Destination(identity: identity, direction: .in, kind: .single, appName: "t", aspects: [])
        dst.proofStrategy = .proveNone
        XCTAssertEqual(dst.proofStrategy, .proveNone)
    }
}
