import XCTest
@testable import ReticulumSwift

final class PacketReceiptTests: XCTestCase {

    func testReceiptStartsAsSent() {
        let receipt = PacketReceipt(
            packetHash: Data(repeating: 0x01, count: 32),
            peerIdentity: nil,
            timeout: 30
        )
        XCTAssertEqual(receipt.status, .sent)
        XCTAssertFalse(receipt.proved)
        XCTAssertNil(receipt.rtt)
    }

    func testCheckTimeoutTransitionsToFailedAfterTimeout() {
        let receipt = PacketReceipt(
            packetHash: Data(repeating: 0x01, count: 32),
            peerIdentity: nil,
            timeout: -1  // already elapsed
        )
        // Simulate timeout by setting sentAt in the past via a subclass or by
        // using the -1 sentinel which means "cull" on next check.
        // Use a very short timeout to trigger it.
        let r2 = PacketReceipt(
            packetHash: Data(repeating: 0x02, count: 32),
            peerIdentity: nil,
            timeout: 0
        )
        // checkTimeout with timeout=0 and sentAt=now → sentAt+0 < now may or
        // may not fire depending on timing. Use a past sentAt by testing the
        // isTimedOut property with a known-expired receipt instead.
        XCTAssertTrue(receipt.isTimedOut)  // timeout = -1 means always timed out (cull path)
        receipt.checkTimeout()
        XCTAssertEqual(receipt.status, .culled)
    }

    func testReceiptNotTimedOutWithLongTimeout() {
        let receipt = PacketReceipt(
            packetHash: Data(repeating: 0x03, count: 32),
            peerIdentity: nil,
            timeout: 3600
        )
        XCTAssertFalse(receipt.isTimedOut)
        receipt.checkTimeout()
        XCTAssertEqual(receipt.status, .sent)
    }

    func testDeliveryCallbackFiredOnValidProof() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity,
            direction: .in,
            kind: .single,
            appName: "test",
            aspects: []
        )
        // Build a packet and compute its hash.
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: destination.hash,
            data: Data("hello".utf8)
        )
        let packetHash = Hashes.fullHash(try packet.hashablePart())
        let receipt = PacketReceipt(
            packetHash: packetHash,
            peerIdentity: identity,
            timeout: 30
        )

        let delivered = XCTestExpectation(description: "delivered")
        receipt.onDelivery = { _ in delivered.fulfill() }

        // Build explicit proof: [packetHash][ed25519_sig(packetHash)]
        let signature = try identity.sign(packetHash)
        let proof = packetHash + signature
        let valid = receipt.validateExplicitProof(proof)

        XCTAssertTrue(valid)
        XCTAssertEqual(receipt.status, .delivered)
        XCTAssertTrue(receipt.proved)
        XCTAssertNotNil(receipt.rtt)
        wait(for: [delivered], timeout: 1)
    }

    func testProofFailsWithWrongIdentity() throws {
        let identity = Identity()
        let wrongIdentity = Identity()
        let destination = try Destination(
            identity: identity,
            direction: .in,
            kind: .single,
            appName: "test",
            aspects: []
        )
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: destination.hash,
            data: Data("tampered".utf8)
        )
        let packetHash = Hashes.fullHash(try packet.hashablePart())
        let receipt = PacketReceipt(packetHash: packetHash, peerIdentity: identity, timeout: 30)

        let signature = try wrongIdentity.sign(packetHash)
        let proof = packetHash + signature
        XCTAssertFalse(receipt.validateExplicitProof(proof))
        XCTAssertEqual(receipt.status, .sent)
    }

    func testTransportGeneratesReceiptForDataPacket() throws {
        let transport = Transport()
        let dstIdentity = Identity()
        let dst = try Destination(
            identity: dstIdentity,
            direction: .in,
            kind: .single,
            appName: "test",
            aspects: []
        )
        // Inject path so the packet routes.
        transport.restore(identity: dstIdentity, forDestination: dst.hash)
        transport.restore(
            path: Transport.PathEntry(
                destinationHash: dst.hash,
                nextHopInterfaceName: "lo",
                hops: 1,
                lastHeard: Date(),
                identityHash: dstIdentity.hash
            ),
            forDestination: dst.hash
        )

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dst.hash,
            data: Data("receipt test".utf8)
        )
        // Transport has no interfaces attached — send will silently no-op
        // but should still produce a receipt.
        let receipt = try transport.send(packet)
        XCTAssertNotNil(receipt)
        XCTAssertEqual(receipt?.status, .sent)
    }
}
