import XCTest
@testable import ReticulumSwift

/// Tests for Packet.send() convenience method (mirrors Python's Packet.send()).
final class PacketSendConvenienceTests: XCTestCase {

    private var tmpDir: URL!
    private var rns: Reticulum?

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-pkt-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        rns?.stop()
        rns = nil
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    final class CapturingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    func testPacketSendViaTransport() throws {
        // Test Transport.send(packet) — the primary Swift API
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["send"])
        t.ownerIdentity = id
        t.restore(identity: id, forDestination: dest.hash)

        let iface = CapturingInterface(name: "cap")
        t.register(interface: iface)

        let plaintext = Data("hello".utf8)
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(plaintext)
        )
        let receipt = try t.send(packet)
        XCTAssertNotNil(receipt, "send should return a receipt for SINGLE DATA packets")
    }

    func testPacketSendConvenienceMethodViaSharedInstance() throws {
        // Set up a shared Reticulum instance
        let config = Reticulum.Configuration(storagePath: tmpDir.appendingPathComponent("storage"))
        let r = Reticulum(configuration: config)
        try r.start()
        rns = r

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["shared"])
        r.transport.ownerIdentity = id
        r.transport.restore(identity: id, forDestination: dest.hash)

        let iface = CapturingInterface(name: "cap")
        r.transport.register(interface: iface)

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(Data("test".utf8))
        )
        // Use the convenience method on Packet
        let receipt = try packet.sendViaShared()
        XCTAssertNotNil(receipt)
    }

    func testPacketResend() throws {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["resend"])
        t.ownerIdentity = id
        t.restore(identity: id, forDestination: dest.hash)

        let iface = CapturingInterface(name: "cap")
        t.register(interface: iface)

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(Data("hello".utf8))
        )

        try t.send(packet, generateReceipt: false)
        let count1 = iface.sent.count

        // Resend the same packet
        try t.send(packet, generateReceipt: false)
        let count2 = iface.sent.count

        XCTAssertEqual(count2, count1 + 1, "resend should send the packet again")
    }
}
