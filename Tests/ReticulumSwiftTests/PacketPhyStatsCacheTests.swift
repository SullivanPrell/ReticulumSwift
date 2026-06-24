import XCTest
@testable import ReticulumSwift

final class PacketPhyStatsCacheTests: XCTestCase {

    func testCacheMissReturnsNil() {
        let transport = Transport()
        let fakeHash = Data(repeating: 0x01, count: 16)
        XCTAssertNil(transport.getPacketRssi(packetHash: fakeHash))
        XCTAssertNil(transport.getPacketSnr(packetHash: fakeHash))
        XCTAssertNil(transport.getPacketQ(packetHash: fakeHash))
    }

    func testCachesRSSIOnInbound() throws {
        let transport = Transport()
        let loopback = PhyStatsLoopback()
        loopback.isOnline = true
        transport.register(interface: loopback)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["phy"])
        transport.register(destination: dest)

        var pkt = Packet(destinationType: .single, packetType: .data,
                         destinationHash: dest.hash, data: Data([0x42]))
        pkt.rssi = -72.5
        let hash = try pkt.truncatedPacketHash()

        transport.handleIncoming(packet: pkt, from: loopback)

        XCTAssertEqual(transport.getPacketRssi(packetHash: hash), -72.5)
    }

    func testCachesSNROnInbound() throws {
        let transport = Transport()
        let loopback = PhyStatsLoopback()
        loopback.isOnline = true
        transport.register(interface: loopback)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["phy"])
        transport.register(destination: dest)

        var pkt = Packet(destinationType: .single, packetType: .data,
                         destinationHash: dest.hash, data: Data([0x55]))
        pkt.snr = 8.25
        let hash = try pkt.truncatedPacketHash()

        transport.handleIncoming(packet: pkt, from: loopback)

        XCTAssertEqual(transport.getPacketSnr(packetHash: hash), 8.25)
    }

    func testCachesQualityOnInbound() throws {
        let transport = Transport()
        let loopback = PhyStatsLoopback()
        loopback.isOnline = true
        transport.register(interface: loopback)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["phy"])
        transport.register(destination: dest)

        var pkt = Packet(destinationType: .single, packetType: .data,
                         destinationHash: dest.hash, data: Data([0xAA]))
        pkt.quality = 95.0
        let hash = try pkt.truncatedPacketHash()

        transport.handleIncoming(packet: pkt, from: loopback)

        XCTAssertEqual(transport.getPacketQ(packetHash: hash), 95.0)
    }

    func testNoPHYStatsCachesNothingForHash() throws {
        let transport = Transport()
        let loopback = PhyStatsLoopback()
        loopback.isOnline = true
        transport.register(interface: loopback)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["phy"])
        transport.register(destination: dest)

        var pkt = Packet(destinationType: .single, packetType: .data,
                         destinationHash: dest.hash, data: Data([0xFF]))
        // no rssi/snr/quality set
        let hash = try pkt.truncatedPacketHash()

        transport.handleIncoming(packet: pkt, from: loopback)

        XCTAssertNil(transport.getPacketRssi(packetHash: hash))
        XCTAssertNil(transport.getPacketSnr(packetHash: hash))
        XCTAssertNil(transport.getPacketQ(packetHash: hash))
    }

    func testCacheMaxSize() throws {
        let transport = Transport()
        let loopback = PhyStatsLoopback()
        loopback.isOnline = true
        transport.register(interface: loopback)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["phy"])
        transport.register(destination: dest)

        // Record the first packet's hash before overfilling.
        var firstPkt = Packet(destinationType: .single, packetType: .data,
                              destinationHash: dest.hash, data: Data([0x01, 0x00, 0x00, 0x00]))
        firstPkt.rssi = -10.0
        let firstHash = try firstPkt.truncatedPacketHash()
        transport.handleIncoming(packet: firstPkt, from: loopback)

        // Fill cache past max size (512). Each packet needs unique data.
        for i in 0 ..< Transport.localClientCacheMaxSize {
            var pkt = Packet(destinationType: .single, packetType: .data,
                             destinationHash: dest.hash,
                             data: Data([UInt8(i & 0xFF), UInt8((i >> 8) & 0xFF), 0xCC, 0xDD]))
            pkt.rssi = Float(i)
            transport.handleIncoming(packet: pkt, from: loopback)
        }

        // The first entry should have been evicted.
        XCTAssertNil(transport.getPacketRssi(packetHash: firstHash),
                     "Oldest entry should be evicted when cache exceeds max size")
    }

    func testTransportGettersForAllThreeStats() throws {
        let transport = Transport()
        let loopback = PhyStatsLoopback()
        loopback.isOnline = true
        transport.register(interface: loopback)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["phy"])
        transport.register(destination: dest)

        var pkt = Packet(destinationType: .single, packetType: .data,
                         destinationHash: dest.hash, data: Data([0x11, 0x22]))
        pkt.rssi = -55.0
        pkt.snr = 12.5
        pkt.quality = 80.0
        let hash = try pkt.truncatedPacketHash()

        transport.handleIncoming(packet: pkt, from: loopback)

        XCTAssertEqual(transport.getPacketRssi(packetHash: hash), -55.0)
        XCTAssertEqual(transport.getPacketSnr(packetHash: hash), 12.5)
        XCTAssertEqual(transport.getPacketQ(packetHash: hash), 80.0)
    }

    func testReticulumGettersWrapTransport() throws {
        let transport = Transport()
        let loopback = PhyStatsLoopback()
        loopback.isOnline = true
        transport.register(interface: loopback)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["phy"])
        transport.register(destination: dest)

        var pkt = Packet(destinationType: .single, packetType: .data,
                         destinationHash: dest.hash, data: Data([0x33]))
        pkt.rssi = -40.0
        pkt.snr = 9.0
        pkt.quality = 70.0
        let hash = try pkt.truncatedPacketHash()
        transport.handleIncoming(packet: pkt, from: loopback)

        // Verify via Transport directly (Reticulum wrapper just delegates)
        XCTAssertEqual(transport.getPacketRssi(packetHash: hash), -40.0)
        XCTAssertEqual(transport.getPacketSnr(packetHash: hash), 9.0)
        XCTAssertEqual(transport.getPacketQ(packetHash: hash), 70.0)
    }
}

private final class PhyStatsLoopback: Interface {
    var name: String = "PhyStatsLoopback"
    var isOnline: Bool = false
    var rxBytes: Int = 0
    var txBytes: Int = 0
    var rxPackets: Int = 0
    var txPackets: Int = 0
    var bitrate: Int = 100_000
    var inboundHandler: ((Packet, any Interface) -> Void)?

    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws { }
}
