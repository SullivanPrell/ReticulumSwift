import XCTest
@testable import ReticulumSwift

final class ProofGenerationTests: XCTestCase {

    func testProveAllSendsProofBackOnSourceInterface() throws {
        let dstIdentity = Identity()
        let dst = try Destination(
            identity: dstIdentity,
            direction: .in,
            kind: .single,
            appName: "test",
            aspects: []
        )
        dst.proofStrategy = .proveAll

        let (tA, tB, _, _) = makePaired()
        tB.register(destination: dst)
        tB.ownerIdentity = dstIdentity

        // Send a DATA packet from A to B.
        let srcIdentity = Identity()
        tA.restore(identity: dstIdentity, forDestination: dst.hash)

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dst.hash,
            data: try dstIdentity.encrypt(Data("hello proof".utf8))
        )

        // Expect a proof to arrive back at A.
        let proofReceived = XCTestExpectation(description: "proof received")
        var receivedReceipt: PacketReceipt?
        let receipt = try tA.send(packet)
        receipt?.onDelivery = { r in
            receivedReceipt = r
            proofReceived.fulfill()
        }

        wait(for: [proofReceived], timeout: 2)
        XCTAssertNotNil(receivedReceipt)
        XCTAssertEqual(receivedReceipt?.status, .delivered)
        XCTAssertTrue(receivedReceipt?.proved ?? false)
        _ = srcIdentity
    }

    func testProveNoneDoesNotSendProof() throws {
        let dstIdentity = Identity()
        let dst = try Destination(
            identity: dstIdentity,
            direction: .in,
            kind: .single,
            appName: "test",
            aspects: []
        )
        dst.proofStrategy = .proveNone

        let (tA, tB, _, _) = makePaired()
        tB.register(destination: dst)
        tB.ownerIdentity = dstIdentity
        tA.restore(identity: dstIdentity, forDestination: dst.hash)

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dst.hash,
            data: try dstIdentity.encrypt(Data("no proof".utf8))
        )
        let receipt = try tA.send(packet)
        XCTAssertNotNil(receipt)

        // Wait a little; proof should NOT arrive.
        let noProof = XCTestExpectation(description: "no proof expected")
        noProof.isInverted = true
        receipt?.onDelivery = { _ in noProof.fulfill() }
        wait(for: [noProof], timeout: 0.5)
        XCTAssertEqual(receipt?.status, .sent)
    }

    func testProveAppCallsCallbackAndProves() throws {
        let dstIdentity = Identity()
        let dst = try Destination(
            identity: dstIdentity,
            direction: .in,
            kind: .single,
            appName: "test",
            aspects: []
        )
        dst.proofStrategy = .proveApp
        dst.onProofRequested = { _ in true }

        let (tA, tB, _, _) = makePaired()
        tB.register(destination: dst)
        tB.ownerIdentity = dstIdentity
        tA.restore(identity: dstIdentity, forDestination: dst.hash)

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dst.hash,
            data: try dstIdentity.encrypt(Data("app proof".utf8))
        )
        let receipt = try tA.send(packet)
        let proved = XCTestExpectation(description: "app-triggered proof")
        receipt?.onDelivery = { _ in proved.fulfill() }
        wait(for: [proved], timeout: 2)
        XCTAssertEqual(receipt?.status, .delivered)
    }

    // MARK: - Helpers

    private func makePaired() -> (Transport, Transport, LoopbackInterface, LoopbackInterface) {
        let tA = Transport(); let tB = Transport()
        let iA = LoopbackInterface(name: "A"); let iB = LoopbackInterface(name: "B")
        iA.paired = iB; iB.paired = iA
        tA.register(interface: iA); tB.register(interface: iB)
        return (tA, tB, iA, iB)
    }
}
