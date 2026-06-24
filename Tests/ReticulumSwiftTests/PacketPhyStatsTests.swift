import XCTest
@testable import ReticulumSwift

/// Tests for PHY stats (RSSI/SNR/quality) carried on received Packets.
/// Mirrors Python's `Packet.get_rssi()`, `Packet.get_snr()`, `Packet.get_q()`.
final class PacketPhyStatsTests: XCTestCase {

    final class RadioInterface: Interface {
        var name: String = "Radio"
        var bitrate: Int = 9600
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?

        // Simulated radio stats (set before emitting a packet)
        var rssi: Float? = nil
        var snr: Float? = nil
        var quality: Float? = nil

        weak var paired: RadioInterface?

        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            var copy = try Packet.unpack(raw)
            // Stamp PHY stats from the sending interface onto the received packet
            copy.rssi = rssi
            copy.snr = snr
            copy.quality = quality
            paired?.inboundHandler?(copy, paired!)
        }
        func start() throws {}
        func stop() {}
    }

    // MARK: - Default nil

    func testPacketPhyStatsNilByDefault() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["phy"])
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dest.hash,
            data: Data("hi".utf8)
        )
        XCTAssertNil(packet.rssi)
        XCTAssertNil(packet.snr)
        XCTAssertNil(packet.quality)
    }

    // MARK: - PHY stats propagate through interface

    func testPhyStatsCarriedOnReceivedPacket() throws {
        let aT = Transport()
        let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["phy"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)

        let aIface = RadioInterface(); aIface.name = "A"
        let bIface = RadioInterface(); bIface.name = "B"
        aIface.paired = bIface; bIface.paired = aIface

        // Set PHY stats on A (the interface that will "transmit")
        aIface.rssi = -85.0
        aIface.snr = 7.5
        aIface.quality = 80.0

        aT.register(interface: aIface)
        bT.register(interface: bIface)

        var receivedPacket: Packet?
        bDest.onPacketReceived = { _, pkt in receivedPacket = pkt }
        bDest.proofStrategy = .proveNone

        let dataPacket = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: bDest.hash,
            data: try bDest.encrypt(Data("hello".utf8))
        )
        try aT.send(dataPacket, generateReceipt: false)

        // Give a brief moment for synchronous loopback delivery
        let deadline = Date().addingTimeInterval(0.5)
        while receivedPacket == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        guard let received = receivedPacket else {
            return XCTFail("packet not delivered")
        }
        XCTAssertEqual(received.rssi, -85.0)
        XCTAssertEqual(received.snr, 7.5)
        XCTAssertEqual(received.quality, 80.0)

        _ = (aT, bT)
    }

    // MARK: - PHY stats nil when interface has none

    func testPhyStatsNilWhenInterfaceHasNoStats() throws {
        let aT = Transport()
        let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["nophy"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)

        let aIface = RadioInterface(); aIface.name = "A"
        let bIface = RadioInterface(); bIface.name = "B"
        aIface.paired = bIface; bIface.paired = aIface
        // Leave PHY stats nil on aIface

        aT.register(interface: aIface)
        bT.register(interface: bIface)

        var receivedPacket: Packet?
        bDest.onPacketReceived = { _, pkt in receivedPacket = pkt }
        bDest.proofStrategy = .proveNone

        let dataPacket = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: bDest.hash,
            data: try bDest.encrypt(Data("hello".utf8))
        )
        try aT.send(dataPacket, generateReceipt: false)

        let deadline = Date().addingTimeInterval(0.5)
        while receivedPacket == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        guard let received = receivedPacket else {
            return XCTFail("packet not delivered")
        }
        XCTAssertNil(received.rssi)
        XCTAssertNil(received.snr)
        XCTAssertNil(received.quality)

        _ = (aT, bT)
    }
}
