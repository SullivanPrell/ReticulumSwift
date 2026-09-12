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

/// `Transport.packet_filter` parity: the six contexts that bypass the hashlist, and the
/// announce type gate.
///
/// Python's filter answers `True` for six contexts before it ever reaches the duplicate
/// check (`Transport.py:1635-1640`), so those frames are neither deduplicated nor recorded.
/// Every one of them repeats legitimately on the wire: a keepalive repeats until the peer
/// answers, a resource part repeats when its window times out, a channel message repeats
/// until the far side acknowledges it. The hashable part of a packet excludes the hop count,
/// so a retransmission hashes identically to the frame it retransmits—which is exactly why
/// Python exempts them rather than relying on them differing.
final class PacketFilterContextExemptionTests: XCTestCase {

    /// `KEEPALIVE`, `RESOURCE_REQ`, `RESOURCE_PRF`, `RESOURCE`, `CACHE_REQUEST`, `CHANNEL`—
    /// the six and only six that `Transport.py:1635-1640` lets through.
    private static let exemptContexts: [Packet.Context] = [
        .keepalive, .resourceRequest, .resourceProof, .resource, .cacheRequest, .channel,
    ]

    private func packet(context: Packet.Context,
                        destinationType: Packet.DestinationType = .single,
                        packetType: Packet.PacketType = .data,
                        hops: UInt8 = 0) -> Packet {
        Packet(destinationType: destinationType,
               packetType: packetType,
               hops: hops,
               destinationHash: Data(repeating: 0x11, count: Constants.truncatedHashLength),
               context: context,
               data: Data([0xFF]))
    }

    // MARK: - The six exemptions

    func testEveryExemptContextSurvivesBeingRepeated() {
        for context in Self.exemptContexts {
            let t = Transport()
            let repeated = packet(context: context)
            XCTAssertTrue(t.filterAndRecord(packet: repeated),
                          "\(context) must pass on first sight")
            XCTAssertTrue(t.filterAndRecord(packet: repeated),
                          """
                          \(context) was dropped as a duplicate. Python returns True for it \
                          before the hashlist is consulted (Transport.py:1635-1640), because \
                          a retransmission of this context is byte-identical to the frame it \
                          retransmits and would otherwise be filtered forever.
                          """)
        }
    }

    func testAnExemptContextPassesEvenWhenItsHashIsAlreadyRecorded() throws {
        // Python stores these hashes like any other—`add_packet_hash` sits past the filter,
        // in `preprocess_inbound` (`Transport.py:1959-1961`). What it never does is consult
        // the entry, so a stored hash has to stay inert for these six.
        for context in Self.exemptContexts {
            let t = Transport()
            let exempt = packet(context: context)
            t.testInsertPacketHash(try exempt.packetHash())
            XCTAssertTrue(t.filterAndRecord(packet: exempt),
                          """
                          \(context) was filtered on a recorded hash. The exemption sits \
                          above the duplicate check, so the hashlist entry must not be read.
                          """)
        }
    }

    func testAContextPythonDoesNotExemptStillDeduplicates() {
        // RESOURCE_ADV (0x02) sits between two exempt values and is deliberately absent from
        // Python's list, which is the point: the exemption is a fixed set, not "anything
        // resource-shaped".
        let t = Transport()
        let advertisement = packet(context: .resourceAdvertisement)
        XCTAssertTrue(t.filterAndRecord(packet: advertisement))
        XCTAssertFalse(t.filterAndRecord(packet: advertisement),
                       "RESOURCE_ADV is not one of the six; it must still deduplicate")
    }

    func testAnOrdinaryDataPacketStillDeduplicates() {
        let t = Transport()
        let ordinary = packet(context: .none)
        XCTAssertTrue(t.filterAndRecord(packet: ordinary))
        XCTAssertFalse(t.filterAndRecord(packet: ordinary))
    }

    // MARK: - Ordering against the hop checks

    func testAnExemptContextPassesEvenPastTheHopCeiling() {
        // Python tests the six contexts BEFORE the PLAIN/GROUP hop ceilings, so a relayed
        // keepalive passes at any hop count. Reproducing the order matters: swapping the two
        // blocks would silently drop these.
        let t = Transport()
        XCTAssertTrue(t.filterAndRecord(packet: packet(context: .keepalive,
                                                       destinationType: .plain,
                                                       hops: 5)))
    }

    func testTheTransportIDFilterStillRunsFirst() {
        // The transport-ID test precedes the exemptions upstream, so a keepalive addressed
        // to a different transport instance is still rejected.
        let t = Transport()
        let addressedElsewhere = Packet(headerType: .type2,
                                        destinationType: .single,
                                        packetType: .data,
                                        transportID: Data(repeating: 0x99,
                                                          count: Constants.truncatedHashLength),
                                        destinationHash: Data(repeating: 0x11,
                                                              count: Constants.truncatedHashLength),
                                        context: .keepalive,
                                        data: Data([0xFF]))
        XCTAssertFalse(t.filterAndRecord(packet: addressedElsewhere),
                       "a packet routed to another transport instance is filtered before "
                       + "the context exemptions are consulted")
    }

    // MARK: - The announce type gate

    func testAPlainAnnounceIsFiltered() {
        // `Transport.py:1650-1653`. An announce only means anything for a SINGLE
        // destination; a PLAIN one is a malformed frame at any hop count, so the ceiling
        // can't apply.
        let t = Transport()
        XCTAssertFalse(t.filterAndRecord(packet: packet(context: .none,
                                                        destinationType: .plain,
                                                        packetType: .announce)),
                       "a PLAIN announce is dropped by the filter, not passed on to be "
                       + "rejected later by announce validation")
    }

    func testAGroupAnnounceIsFiltered() {
        // `Transport.py:1663-1666`.
        let t = Transport()
        XCTAssertFalse(t.filterAndRecord(packet: packet(context: .none,
                                                        destinationType: .group,
                                                        packetType: .announce)))
    }

    func testAPlainDataPacketAtOneHopStillPasses() {
        // The hop ceiling is `> 1`, and a path request arrives at one hop.
        let t = Transport()
        XCTAssertTrue(t.filterAndRecord(packet: packet(context: .none,
                                                       destinationType: .plain,
                                                       hops: 1)))
    }

    func testAPlainDataPacketPastTheHopCeilingIsFiltered() {
        let t = Transport()
        XCTAssertFalse(t.filterAndRecord(packet: packet(context: .none,
                                                        destinationType: .plain,
                                                        hops: 2)))
    }

    // MARK: - PLAIN and GROUP never reach the duplicate check

    func testAPlainPacketIsNotDeduplicated() {
        // Python's PLAIN branch returns True outright below the hop ceiling
        // (`Transport.py:1654-1655`), so it never consults the hashlist. Path requests are
        // PLAIN, and two identical ones are ordinary traffic.
        let t = Transport()
        let request = packet(context: .none, destinationType: .plain)
        XCTAssertTrue(t.filterAndRecord(packet: request))
        XCTAssertTrue(t.filterAndRecord(packet: request),
                      "a repeated PLAIN packet is passed by Python, not filtered")
    }

    func testAGroupPacketIsNotDeduplicated() {
        // `Transport.py:1667-1668`, the same shape as PLAIN.
        let t = Transport()
        let broadcast = packet(context: .none, destinationType: .group)
        XCTAssertTrue(t.filterAndRecord(packet: broadcast))
        XCTAssertTrue(t.filterAndRecord(packet: broadcast))
    }

    // MARK: - Shared-instance clients filter nothing

    func testAClientOfASharedInstanceFiltersNothing() {
        // `Transport.py:1625-1627`. The instance already filtered; repeating the work on the
        // client only drops packets it has vetted.
        let t = Transport()
        t.isConnectedToSharedInstance = true
        let ordinary = packet(context: .none)
        XCTAssertTrue(t.filterAndRecord(packet: ordinary))
        XCTAssertTrue(t.filterAndRecord(packet: ordinary),
                      "a client defers filtering to its shared instance")
    }

    func testAClientOfASharedInstanceRecordsNothing() throws {
        // `add_packet_hash` is itself a no-op on a client (`Transport.py:1619-1621`), so the
        // hashlist a client persists stays empty.
        let t = Transport()
        t.isConnectedToSharedInstance = true
        let ordinary = packet(context: .none)
        _ = t.filterAndRecord(packet: ordinary)
        XCTAssertFalse(t.testContainsPacketHash(try ordinary.packetHash()))
    }

    // MARK: - The public filter answers the same question

    func testThePublicFilterAgreesWithTheRecorderOnEveryExemption() {
        // One implementation backs both spellings; this pins that they can't drift apart.
        for context in Self.exemptContexts {
            let t = Transport()
            let exempt = packet(context: context)
            _ = t.filterAndRecord(packet: exempt)
            XCTAssertTrue(t.packetFilter(exempt), "\(context) disagrees across the two entry points")
        }
        let plainAnnounce = packet(context: .none, destinationType: .plain, packetType: .announce)
        XCTAssertFalse(Transport().packetFilter(plainAnnounce))
    }

    // MARK: - A link this node carries stays out of the list

    func testAPacketForACarriedLinkIsNotRecorded() throws {
        // `Transport.py:1944-1952`. On shared media this node can see a relayed link packet
        // before its turn to route it; recording the hash then filters the copy it must
        // forward, and transport through this node stalls.
        let t = Transport()
        let linkID = Data(repeating: 0x5A, count: Constants.truncatedHashLength)
        let relayed = Packet(destinationType: .link,
                             packetType: .data,
                             destinationHash: linkID,
                             context: .none,
                             data: Data([0xAB, 0xCD]))
        t.restore(linkRoute: Transport.LinkRoute(linkID: linkID,
                                                 initiatorSideInterfaceName: "a",
                                                 responderSideInterfaceName: "b",
                                                 destinationHash: Data(repeating: 0x77,
                                                                       count: Constants.truncatedHashLength),
                                                 lastHeard: Date()))
        XCTAssertTrue(t.filterAndRecord(packet: relayed))
        XCTAssertFalse(t.testContainsPacketHash(try relayed.packetHash()),
                       "a packet whose destination is in the link table must stay out of "
                       + "the hashlist until this node knows its turn to route it has come")
        XCTAssertTrue(t.filterAndRecord(packet: relayed),
                      "and so it must still pass on a second sighting")
    }

    func testAPacketForAnUnknownLinkIsRecordedNormally() throws {
        // The control: same shape, no link-table entry, so the ordinary rule holds.
        let t = Transport()
        let ordinary = Packet(destinationType: .link,
                              packetType: .data,
                              destinationHash: Data(repeating: 0x5B,
                                                    count: Constants.truncatedHashLength),
                              context: .none,
                              data: Data([0xAB, 0xCD]))
        XCTAssertTrue(t.filterAndRecord(packet: ordinary))
        XCTAssertTrue(t.testContainsPacketHash(try ordinary.packetHash()))
        XCTAssertFalse(t.filterAndRecord(packet: ordinary))
    }
}
