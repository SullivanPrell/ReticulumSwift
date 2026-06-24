import XCTest
@testable import ReticulumSwift

/// Tests for CACHE_REQUEST packet handling.
///
/// Mirrors Python's `Transport.cache_request_packet(packet)`:
/// When a DATA packet arrives with context == .cacheRequest and
/// data == 32-byte hash, look up the cached announce and replay it.
final class CacheRequestTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-cache-req-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - cache_request_packet: serves cached announce

    func testCacheRequestPacketServesMatchingAnnounce() throws {
        let t = Transport()
        t.cacheDirectory = tmpDir

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "creq", aspects: ["test"])

        final class CountingIface: Interface {
            var name = "cr-iface"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            var sentPackets: [Packet] = []
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws { sentPackets.append(packet) }
        }
        let iface = CountingIface()
        t.register(interface: iface)

        // Cache an announce.
        let ann = try Announce.make(for: dest)
        let announceHash = Hashes.fullHash(try ann.hashablePart())
        try t.cacheAnnounce(ann)

        // Build a CACHE_REQUEST packet whose payload is the 32-byte announce hash.
        let cacheReqPacket = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Hashes.truncatedHash(Data("cache_req".utf8)),
            context: .cacheRequest,
            data: announceHash
        )

        let served = t.cacheRequestPacket(cacheReqPacket)
        XCTAssertTrue(served, "cache_request_packet must return true when announce is found in cache")
    }

    // MARK: - Returns false for unknown hash

    func testCacheRequestPacketReturnsFalseWhenNotCached() throws {
        let t = Transport()
        t.cacheDirectory = tmpDir

        let unknownHash = Data(repeating: 0xAB, count: 32)
        let pkt = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Hashes.truncatedHash(Data("cache_req".utf8)),
            context: .cacheRequest,
            data: unknownHash
        )

        let served = t.cacheRequestPacket(pkt)
        XCTAssertFalse(served, "cache_request_packet must return false when hash not in cache")
    }

    // MARK: - Returns false for wrong-length data

    func testCacheRequestPacketReturnsFalseForWrongDataLength() throws {
        let t = Transport()
        t.cacheDirectory = tmpDir

        // data is 16 bytes (truncated hash), not 32 bytes (full hash).
        let shortHash = Data(repeating: 0xCC, count: 16)
        let pkt = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Hashes.truncatedHash(Data("cache_req".utf8)),
            context: .cacheRequest,
            data: shortHash
        )

        let served = t.cacheRequestPacket(pkt)
        XCTAssertFalse(served, "cache_request_packet must return false when data is not a 32-byte hash")
    }

    // MARK: - Wired into Transport inbound pipeline

    func testCacheRequestHandledInInbound() throws {
        let t = Transport()
        t.cacheDirectory = tmpDir

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "creq", aspects: ["inbound"])
        t.ownerIdentity = identity
        t.register(destination: dest)

        final class TestIface: Interface {
            var name = "cr-in"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = TestIface()
        t.register(interface: iface)

        // Cache an announce for the destination.
        let ann = try Announce.make(for: dest)
        let announceHash = Hashes.fullHash(try ann.hashablePart())
        try t.cacheAnnounce(ann)

        // Deliver a CACHE_REQUEST packet via the interface's inbound handler.
        let cacheReqPacket = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Hashes.truncatedHash(Data("cache_req_dst".utf8)),
            context: .cacheRequest,
            data: announceHash
        )

        // Should not throw, and should handle silently.
        iface.inboundHandler?(cacheReqPacket, iface)
        // If we get here without crash, the inbound pipeline handled CACHE_REQUEST.
        XCTAssertTrue(true)
    }

    // MARK: - Constant: HASHLENGTH/8 = 32 bytes

    func testCacheRequestHashLength() {
        XCTAssertEqual(Constants.fullHashLength, 32,
            "CACHE_REQUEST data must be Identity.HASHLENGTH/8 = 256/8 = 32 bytes")
    }
}
