import XCTest
@testable import ReticulumSwift

/// Tests for `Transport.cacheRequest(packetHash:destination:)`.
///
/// Mirrors Python's `Transport.cache_request(packet_hash, destination)`:
/// - If the packet hash is found in the local announce cache → replay locally.
/// - If not found → send a CACHE_REQUEST DATA packet to the destination.
final class CacheRequestOutboundTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-creq-out-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTransportWithIface() -> (Transport, SpyIface) {
        let t = Transport()
        t.cacheDirectory = tmpDir
        let iface = SpyIface()
        t.register(interface: iface)
        return (t, iface)
    }

    final class SpyIface: Interface {
        var name = "spy"; var bitrate = 0; var isOnline = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sentPackets: [Packet] = []
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sentPackets.append(packet) }
    }

    // MARK: - Local cache hit: replay locally, do NOT send over interface

    func testCacheRequestReplayesLocallyOnCacheHit() throws {
        let (t, spy) = makeTransportWithIface()

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "creq", aspects: ["out", "hit"])
        t.register(destination: dest)
        t.ownerIdentity = identity

        let ann = try Announce.make(for: dest)
        let announceHash = Hashes.fullHash(try ann.hashablePart())
        try t.cacheAnnounce(ann)

        let queryDest = try Destination(identity: Identity(), direction: .in, kind: .single,
                                        appName: "creq", aspects: ["peer"])
        t.cacheRequest(packetHash: announceHash, destination: queryDest)

        // Cache hit: the packet must NOT be sent over the interface.
        XCTAssertTrue(spy.sentPackets.isEmpty,
            "cacheRequest must NOT send a network packet when found in local cache")
    }

    // MARK: - Cache miss: sends CACHE_REQUEST packet to the destination

    func testCacheRequestSendsNetworkPacketOnCacheMiss() throws {
        let (t, spy) = makeTransportWithIface()

        let peerIdentity = Identity()
        let queryDest = try Destination(identity: peerIdentity, direction: .in, kind: .single,
                                        appName: "creq", aspects: ["peer"])
        // Register a path so the packet can be routed.
        let path = Transport.PathEntry(
            destinationHash: queryDest.hash,
            nextHopInterfaceName: spy.name,
            hops: 1,
            lastHeard: Date(),
            identityHash: peerIdentity.hash
        )
        t.restore(path: path, forDestination: queryDest.hash)
        t.restore(identity: peerIdentity, forDestination: queryDest.hash)

        let unknownHash = Data(repeating: 0xAB, count: 32)
        t.cacheRequest(packetHash: unknownHash, destination: queryDest)

        // Cache miss: a CACHE_REQUEST packet must be sent.
        XCTAssertFalse(spy.sentPackets.isEmpty,
            "cacheRequest must send a network packet when hash not in local cache")
        let sent = spy.sentPackets.first!
        XCTAssertEqual(sent.context, .cacheRequest,
            "sent packet must have cacheRequest context")
        XCTAssertEqual(sent.data, unknownHash,
            "sent packet payload must be the requested hash")
        XCTAssertEqual(sent.destinationHash, queryDest.hash,
            "sent packet must be addressed to the queried destination")
    }

    // MARK: - Cache miss with no path: packet is still constructed with correct fields

    func testCacheRequestPacketFieldsOnCacheMiss() throws {
        let (t, spy) = makeTransportWithIface()

        let peerIdentity = Identity()
        let queryDest = try Destination(identity: peerIdentity, direction: .in, kind: .single,
                                        appName: "creq", aspects: ["fields"])
        let path = Transport.PathEntry(
            destinationHash: queryDest.hash,
            nextHopInterfaceName: spy.name,
            hops: 1,
            lastHeard: Date(),
            identityHash: peerIdentity.hash
        )
        t.restore(path: path, forDestination: queryDest.hash)
        t.restore(identity: peerIdentity, forDestination: queryDest.hash)

        let hash = Data(repeating: 0x42, count: 32)
        t.cacheRequest(packetHash: hash, destination: queryDest)

        let sent = spy.sentPackets.first!
        XCTAssertEqual(sent.packetType, .data)
        XCTAssertEqual(sent.context, .cacheRequest)
        XCTAssertEqual(sent.data.count, 32,
            "CACHE_REQUEST payload must be 32 bytes (full hash)")
    }
}
