import XCTest
@testable import ReticulumSwift

/// Tests for Packet.prove(destination:), Packet.resend(), and
/// Destination.proveForPacket(_:).
///
/// Python reference:
///   Packet.prove(destination)  → generates and sends a proof via transport
///   Packet.resend()            → re-sends the packet via the shared transport
///   Destination.prove_for_packet(packet) → calls packet.prove(self)
final class PacketProveResendTests: XCTestCase {

    // MARK: - Helpers

    private var tmpDir: URL!
    private var rns: Reticulum?

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-prove-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        rns?.stop()
        rns = nil
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func startReticulum() throws -> Reticulum {
        let cfg = Reticulum.Configuration(storagePath: tmpDir.appendingPathComponent("storage"))
        let r = Reticulum(configuration: cfg)
        try r.start()
        rns = r
        return r
    }

    final class RecordingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []
        weak var paired: RecordingInterface?
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws {
            sent.append(packet)
            if let paired, let raw = try? packet.pack(), let copy = try? Packet.unpack(raw) {
                paired.inboundHandler?(copy, paired)
            }
        }
    }

    // MARK: - receivingInterface is set on delivered packets

    func testReceivingInterfaceSetOnDeliveredPacket() throws {
        let tA = Transport()
        let tB = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["prove"])
        tB.ownerIdentity = bId
        tB.register(destination: bDest)

        let ifA = RecordingInterface(name: "A"); let ifB = RecordingInterface(name: "B")
        ifA.paired = ifB; ifB.paired = ifA
        tA.register(interface: ifA); tB.register(interface: ifB)

        var receivedPacket: Packet?
        let received = XCTestExpectation(description: "packet received")
        bDest.onPacketReceived = { _, pkt in
            receivedPacket = pkt
            received.fulfill()
        }

        tA.restore(identity: bId, forDestination: bDest.hash)
        let pkt = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: bDest.hash,
            data: try bId.encrypt(Data("hello".utf8))
        )
        try tA.send(pkt)
        wait(for: [received], timeout: 1.0)

        XCTAssertNotNil(receivedPacket?.receivingInterface,
                        "Transport must stamp receivingInterface on delivered packets")
        XCTAssertEqual(receivedPacket?.receivingInterface?.name, "B")
    }

    // MARK: - Packet.prove sends proof back

    func testPacketProveWithProveAppStrategy() throws {
        let tA = Transport()
        let tB = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["prove-app"])
        bDest.proofStrategy = .proveApp
        tB.ownerIdentity = bId
        tB.register(destination: bDest)

        let ifA = RecordingInterface(name: "A"); let ifB = RecordingInterface(name: "B")
        ifA.paired = ifB; ifB.paired = ifA
        tA.register(interface: ifA); tB.register(interface: ifB)

        // App manually calls prove() on the received packet.
        let proofDelivered = XCTestExpectation(description: "proof delivered")
        bDest.onPacketReceived = { _, pkt in
            // Manually prove the packet (PROVE_APP strategy)
            pkt.prove(destination: bDest)
        }

        tA.restore(identity: bId, forDestination: bDest.hash)
        let pkt = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: bDest.hash,
            data: try bId.encrypt(Data("prove me".utf8))
        )
        let receipt = try tA.send(pkt)
        receipt?.onDelivery = { _ in proofDelivered.fulfill() }

        wait(for: [proofDelivered], timeout: 1.0)
        XCTAssertEqual(receipt?.status, .delivered)
        XCTAssertTrue(receipt?.proved ?? false)
    }

    // MARK: - Destination.proveForPacket is equivalent to Packet.prove

    func testDestinationProveForPacketDeliversProof() throws {
        let tA = Transport()
        let tB = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["dest-prove"])
        bDest.proofStrategy = .proveApp
        tB.ownerIdentity = bId
        tB.register(destination: bDest)

        let ifA = RecordingInterface(name: "A"); let ifB = RecordingInterface(name: "B")
        ifA.paired = ifB; ifB.paired = ifA
        tA.register(interface: ifA); tB.register(interface: ifB)

        let proofDelivered = XCTestExpectation(description: "proof via proveForPacket")
        bDest.onPacketReceived = { _, pkt in
            // Use Destination.proveForPacket instead of packet.prove(destination:)
            bDest.proveForPacket(pkt)
        }

        tA.restore(identity: bId, forDestination: bDest.hash)
        let pkt = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: bDest.hash,
            data: try bId.encrypt(Data("dest prove".utf8))
        )
        let receipt = try tA.send(pkt)
        receipt?.onDelivery = { _ in proofDelivered.fulfill() }

        wait(for: [proofDelivered], timeout: 1.0)
        XCTAssertEqual(receipt?.status, .delivered,
                       "Destination.proveForPacket must result in a delivered receipt")
    }

    // MARK: - Packet.prove without receivingInterface is a no-op

    func testProveWithoutReceivingInterfaceIsNoOp() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["noop"])
        // Packet has no receivingInterface — prove() must not crash
        let pkt = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: dest.hash,
            data: Data("no-op".utf8)
        )
        XCTAssertNil(pkt.receivingInterface)
        pkt.prove(destination: dest)  // must not throw or crash
    }

    // MARK: - Packet.resend

    func testResendReturnsNewReceipt() throws {
        let _ = try startReticulum()
        guard let transport = Reticulum.shared?.transport else {
            XCTFail("shared transport must be available")
            return
        }

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["resend"])
        transport.ownerIdentity = id
        transport.restore(identity: id, forDestination: dest.hash)

        let iface = RecordingInterface(name: "out")
        transport.register(interface: iface)

        let pkt = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(Data("resend me".utf8))
        )
        let r1 = try pkt.sendViaShared()
        let r2 = try pkt.resend()

        // Both calls should produce receipts (or both nil if route is unavailable)
        // but resend() must not throw.
        XCTAssertNotNil(r1, "initial send must return a receipt")
        XCTAssertNotNil(r2, "resend must return a receipt")
    }

    func testResendIsFunctionallyEquivalentToSendViaShared() throws {
        let _ = try startReticulum()
        guard let transport = Reticulum.shared?.transport else { return }

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["resend2"])
        transport.ownerIdentity = id
        transport.restore(identity: id, forDestination: dest.hash)

        let iface = RecordingInterface(name: "r")
        transport.register(interface: iface)

        let pkt = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(Data("r".utf8))
        )
        let countBefore = iface.sent.count
        try pkt.resend()
        let countAfter = iface.sent.count
        XCTAssertGreaterThan(countAfter, countBefore,
                             "resend() must cause a packet to be transmitted")
    }
}
