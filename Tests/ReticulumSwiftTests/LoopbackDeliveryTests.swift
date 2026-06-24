import XCTest
@testable import ReticulumSwift

/// Tests for packet delivery to locally registered destinations (loopback).
/// When A sends to a destination that A itself has registered, it should
/// be delivered locally without going to an interface.
final class LoopbackDeliveryTests: XCTestCase {

    func testPacketDeliveredToLocalDestination() throws {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["loopback"])
        t.ownerIdentity = id
        t.register(destination: dest)
        t.restore(identity: id, forDestination: dest.hash)

        let received = expectation(description: "received")
        var receivedData: Data?
        dest.onPacketReceived = { data, _ in receivedData = data; received.fulfill() }

        let plaintext = Data("self-delivery".utf8)
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(plaintext)
        )
        try t.send(packet, generateReceipt: false)
        wait(for: [received], timeout: 0.5)

        XCTAssertEqual(receivedData, plaintext)
    }

    func testProofGeneratedForLocalSelf() throws {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["selfproof"])
        t.ownerIdentity = id
        t.register(destination: dest)
        t.restore(identity: id, forDestination: dest.hash)

        dest.proofStrategy = .proveAll

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(Data("self".utf8))
        )

        let delivered = expectation(description: "delivered")
        let receipt = try t.send(packet)
        receipt?.onDelivery = { _ in delivered.fulfill() }
        wait(for: [delivered], timeout: 1.0)

        XCTAssertEqual(receipt?.status, .delivered)
    }
}
