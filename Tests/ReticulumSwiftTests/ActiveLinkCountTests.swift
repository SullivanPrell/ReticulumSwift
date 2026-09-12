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

/// `active_link_count`—the validated subset of the link table, and the `(N active)` suffix
/// `rnstatus` renders beside the table size.
///
/// Upstream's own implementation reads the wrong operand:
/// `sum(1 for e in (True for entry in Transport.link_table if entry[IDX_LT_VALIDATED]))`
/// (`Transport.py:3215`) iterates a dict, so `entry` is a link ID and `entry[7]` is that ID's
/// eighth byte rather than the validated flag. It reports roughly 255 of every 256 entries as
/// active however many the relay verified. This port counts the entries that expression was
/// meant to count, which needs `LinkRoute.validated` to mean what it says—see
/// `RelayLinkProofValidationTests`.
final class ActiveLinkCountTests: XCTestCase {

    private final class Hop: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}
    }

    private func route(_ t: Transport, _ iface: Hop, id: UInt8, validated: Bool) {
        var r = Transport.LinkRoute(linkID: Data(repeating: id, count: Constants.truncatedHashLength),
                                    initiatorSideInterface: iface,
                                    responderSideInterface: iface,
                                    initiatorSideInterfaceName: iface.name,
                                    responderSideInterfaceName: iface.name,
                                    destinationHash: Data(repeating: id, count: Constants.truncatedHashLength),
                                    lastHeard: Date())
        r.validated = validated
        t.restore(linkRoute: r)
    }

    // MARK: - The count

    func testAnEmptyLinkTableHasNoActiveLinks() {
        XCTAssertEqual(Transport().getActiveLinkCount(), 0)
    }

    func testOnlyValidatedEntriesCount() {
        let t = Transport()
        let iface = Hop(name: "r")
        t.register(interface: iface)
        route(t, iface, id: 0x01, validated: true)
        route(t, iface, id: 0x02, validated: false)
        route(t, iface, id: 0x03, validated: true)

        XCTAssertEqual(t.getLinkCount(), 3, "all three are in the table")
        XCTAssertEqual(t.getActiveLinkCount(), 2,
                       "two of them carry a proof this node verified")
    }

    func testAnUnvalidatedTableReportsZeroActive() {
        let t = Transport()
        let iface = Hop(name: "r")
        t.register(interface: iface)
        // Both link IDs have a non-zero eighth byte, which is what upstream's expression
        // actually tests. Reproducing that bug would report 2 here.
        route(t, iface, id: 0x08, validated: false)
        route(t, iface, id: 0x09, validated: false)

        XCTAssertEqual(t.getLinkCount(), 2)
        XCTAssertEqual(t.getActiveLinkCount(), 0,
                       "no proof has been validated, so nothing is active")
    }

    // MARK: - The management API and the RPC verb

    func testTheManagementAPIExposesIt() {
        let t = Transport()
        let iface = Hop(name: "r")
        t.register(interface: iface)
        route(t, iface, id: 0x21, validated: true)
        XCTAssertEqual(t.getActiveLinkCount(), 1)
    }

    func testTheRPCVerbAnswersTheCount() throws {
        let t = Transport()
        let iface = Hop(name: "r")
        t.register(interface: iface)
        route(t, iface, id: 0x31, validated: true)
        route(t, iface, id: 0x32, validated: false)

        let server = RPCServer(port: 37431, authkey: Data(repeating: 0, count: 32))
        server.transport = t
        let call = try MsgPack.encode(.map([(.string("get"), .string("active_link_count"))]))
        // Python: `if path == "active_link_count": self.rpc_return(conn,
        // self.get_active_link_count())` (Reticulum.py:1295). Without the verb the default
        // path answers nil, and a Python peer silently drops the "(N active)" suffix.
        XCTAssertEqual(try MsgPack.decode(server.respond(to: call)).asInt, 1)
    }
}
