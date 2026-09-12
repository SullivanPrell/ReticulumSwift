//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest
@testable import ReticulumSwift

/// Tests for Transport management utilities: getPathTable, getLinkCount.
///
/// Mirrors Python's Reticulum.get_path_table / get_link_count.
final class TransportManagementTests: XCTestCase {

    // MARK: - getPathTable

    func testGetPathTableEmptyWhenNoPaths() {
        let transport = Transport()
        XCTAssertTrue(transport.getPathTable().isEmpty)
    }

    func testGetPathTableContainsRestoredPath() throws {
        let transport = Transport()
        let destHash = Data(repeating: 0xAB, count: 16)
        let identity = Identity()

        transport.restore(
            path: Transport.PathEntry(
                destinationHash: destHash,
                nextHopInterfaceName: "eth0",
                hops: 2,
                lastHeard: Date(),
                identityHash: identity.hash
            ),
            forDestination: destHash
        )

        let table = transport.getPathTable()
        XCTAssertEqual(table.count, 1)
        XCTAssertEqual(table[0].destinationHash, destHash)
        XCTAssertEqual(table[0].hops, 2)
        XCTAssertEqual(table[0].interfaceName, "eth0")
    }

    func testGetPathTableMaxHopsFilter() throws {
        let transport = Transport()
        let h1 = Data(repeating: 0x01, count: 16)
        let h2 = Data(repeating: 0x02, count: 16)
        let id = Identity()

        transport.restore(path: .init(destinationHash: h1, nextHopInterfaceName: "lo",
                                      hops: 1, lastHeard: Date(), identityHash: id.hash),
                          forDestination: h1)
        transport.restore(path: .init(destinationHash: h2, nextHopInterfaceName: "lo",
                                      hops: 5, lastHeard: Date(), identityHash: id.hash),
                          forDestination: h2)

        let filtered = transport.getPathTable(maxHops: 2)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].destinationHash, h1)
    }

    func testGetPathTableNilMaxHopsReturnsAll() throws {
        let transport = Transport()
        let id = Identity()
        for i in UInt8(0) ..< 5 {
            let h = Data(repeating: i, count: 16)
            transport.restore(path: .init(destinationHash: h, nextHopInterfaceName: "lo",
                                          hops: i + 1, lastHeard: Date(), identityHash: id.hash),
                              forDestination: h)
        }
        XCTAssertEqual(transport.getPathTable(maxHops: nil).count, 5)
    }

    // MARK: - getLinkCount

    func testGetLinkCountZeroWhenNoLinks() {
        let transport = Transport()
        XCTAssertEqual(transport.getLinkCount(), 0)
    }

    // MARK: - getInterfaceStats

    func testGetInterfaceStatsReturnsRegisteredInterfaces() throws {
        let transport = Transport()
        let iface = LinkCountLoopback(name: "eth0")
        transport.register(interface: iface)

        let stats = transport.getInterfaceStats()
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats[0].name, "eth0")
        XCTAssertTrue(stats[0].isOnline)
    }

    func testGetInterfaceStatsEmpty() {
        let transport = Transport()
        XCTAssertTrue(transport.getInterfaceStats().isEmpty)
    }

    // MARK: - dropAllPaths

    func testDropAllPathsViaTransportHash() throws {
        let transport = Transport()
        let id = Identity()
        let transportHash = Data(repeating: 0xAB, count: 16)

        let h1 = Data(repeating: 0x01, count: 16)
        let h2 = Data(repeating: 0x02, count: 16)

        transport.restore(path: .init(destinationHash: h1, nextHopInterfaceName: "lo",
                                      hops: 1, lastHeard: Date(), identityHash: id.hash,
                                      nextHopTransportID: transportHash),
                          forDestination: h1)
        transport.restore(path: .init(destinationHash: h2, nextHopInterfaceName: "lo",
                                      hops: 1, lastHeard: Date(), identityHash: id.hash),
                          forDestination: h2)

        transport.dropAllPaths(via: transportHash)

        XCTAssertFalse(transport.hasPath(to: h1), "path via transportHash should be removed")
        XCTAssertTrue(transport.hasPath(to: h2), "path not via transportHash should remain")
    }

    // MARK: - dropAnnounceQueues

    func testDropAnnounceQueuesClearsQueues() throws {
        let transport = Transport()
        // Just verify the call doesn't crash.
        transport.dropAnnounceQueues()
        XCTAssertEqual(transport.getPathTable().count, 0)
    }

    // MARK: - getLinkCount

    /// A link this node terminates is held in `links`, not the link table, so it moves
    /// `activeLinks` and leaves `getLinkCount()` at zero. `LinkTableCountTests` covers the
    /// relayed case and the distinction between the two counts.
    func testAnEstablishedLinkIsRegisteredButAddsNoLinkTableEntry() throws {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "lc")
        bT.ownerIdentity = bId; bT.register(destination: bDest)

        let a = LinkCountLoopback(name: "a"); let b = LinkCountLoopback(name: "b")
        a.paired = b; b.paired = a
        aT.register(interface: a); bT.register(interface: b)

        let aE = expectation(description: "aE"); let bE = expectation(description: "bE")
        aT.onLinkEstablished = { _ in aE.fulfill() }
        bT.onLinkEstablished = { _ in bE.fulfill() }
        _ = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)

        XCTAssertEqual(aT.activeLinks.count, 1, "the initiator holds the link")
        XCTAssertEqual(bT.activeLinks.count, 1, "so does the responder")
        XCTAssertEqual(aT.getLinkCount(), 0,
                       "neither end relays it, so Python's link_table stays empty on both")
        XCTAssertEqual(bT.getLinkCount(), 0)
    }
}

private final class LinkCountLoopback: Interface {
    var name: String; var bitrate: Int = 0; var isOnline: Bool = true
    weak var paired: LinkCountLoopback?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {
        let raw = try packet.pack(); let copy = try Packet.unpack(raw)
        paired?.inboundHandler?(copy, paired!)
    }
}
