import XCTest
@testable import ReticulumSwift

/// Tests for implicit proof behavior (Python default: `Reticulum.__use_implicit_proof = True`).
///
/// Implicit proof wire format: just the 64-byte Ed25519 signature (no hash prefix).
/// Explicit proof wire format: 32-byte packet hash + 64-byte signature.
///
/// The Python default is implicit proof. Both formats must be validated correctly.
final class ImplicitProofTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?

        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    private func makePaired() -> (Transport, Transport, LoopbackInterface, LoopbackInterface) {
        let a = Transport(); let b = Transport()
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        a.register(interface: aI); b.register(interface: bI)
        return (a, b, aI, bI)
    }

    // MARK: - Proof length constants

    func testImplicitProofLength() {
        XCTAssertEqual(PacketReceipt.implicitProofLength, Constants.signatureLength,
            "Implicit proof is signature only (64 bytes)")
    }

    func testExplicitProofLength() {
        XCTAssertEqual(PacketReceipt.explicitProofLength,
                       Constants.fullHashLength + Constants.signatureLength,
                       "Explicit proof is hash + signature (96 bytes)")
    }

    // MARK: - Implicit proof round-trip

    func testImplicitProofValidatedByReceipt() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["imp"])
        let (tA, tB, _, _) = makePaired()
        tB.register(destination: dest)
        tB.ownerIdentity = id
        tA.restore(identity: id, forDestination: dest.hash)

        dest.proofStrategy = .proveAll

        let packet = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(Data("implicit".utf8))
        )

        let saved = Reticulum.useImplicitProof
        Reticulum.useImplicitProof = true
        defer { Reticulum.useImplicitProof = saved }

        let delivered = expectation(description: "delivered")
        let receipt = try tA.send(packet)
        receipt?.onDelivery = { _ in delivered.fulfill() }
        wait(for: [delivered], timeout: 1.0)

        XCTAssertEqual(receipt?.status, .delivered)
        XCTAssertTrue(receipt?.proved ?? false)
        _ = (tA, tB)
    }

    // MARK: - Explicit proof round-trip

    func testExplicitProofValidatedByReceipt() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["exp"])
        let (tA, tB, _, _) = makePaired()
        tB.register(destination: dest)
        tB.ownerIdentity = id
        tA.restore(identity: id, forDestination: dest.hash)

        dest.proofStrategy = .proveAll

        let packet = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(Data("explicit".utf8))
        )

        let saved = Reticulum.useImplicitProof
        Reticulum.useImplicitProof = false
        defer { Reticulum.useImplicitProof = saved }

        let delivered = expectation(description: "delivered")
        let receipt = try tA.send(packet)
        receipt?.onDelivery = { _ in delivered.fulfill() }
        wait(for: [delivered], timeout: 1.0)

        XCTAssertEqual(receipt?.status, .delivered)
        XCTAssertTrue(receipt?.proved ?? false)
        _ = (tA, tB)
    }

    // MARK: - Default is implicit

    func testDefaultIsImplicitProof() {
        XCTAssertTrue(Reticulum.useImplicitProof,
            "useImplicitProof must default to true (matches Python's default)")
    }
}
