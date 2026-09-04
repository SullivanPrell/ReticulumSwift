import XCTest
@testable import ReticulumSwift

/// `link_count` reports the size of the transport link table, not the number of links this
/// node holds.
///
/// Python is unambiguous: `def link_count(): return len(Transport.link_table)`
/// (`Transport.py`). `link_table` holds one entry per link this node *relays*, created in
/// `inbound` when it forwards a link request and swept when the entry goes stale. A link whose
/// endpoint is this node never appears there at all.
///
/// This port returned `links.values.filter { $0.status == .active }.count`—the links this
/// node owns, which is a different quantity and, on a transport node carrying traffic for
/// others, an unrelated one. `rnstatus` prints the value as "N entries in link table", so a
/// Python operator read the wrong number under the right label.
final class LinkTableCountTests: XCTestCase {

    final class HopInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        weak var paired: HopInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            paired?.inboundHandler?(try Packet.unpack(raw), paired!)
        }
    }

    private func wire(_ a: HopInterface, _ b: HopInterface) { a.paired = b; b.paired = a }

    // MARK: - A link this node terminates isn't in the link table

    func testADirectLinkAddsNothingToEitherSideLinkTable() throws {
        let aT = Transport(), bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "lc")
        bT.ownerIdentity = bId
        bT.register(destination: bDest)

        let a = HopInterface(name: "a"), b = HopInterface(name: "b")
        wire(a, b)
        aT.register(interface: a)
        bT.register(interface: b)

        let aE = expectation(description: "initiator"), bE = expectation(description: "responder")
        aT.onLinkEstablished = { _ in aE.fulfill() }
        bT.onLinkEstablished = { _ in bE.fulfill() }
        _ = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)

        XCTAssertEqual(aT.getLinkCount(), 0,
                       """
                       neither end relays this link, so Python's link_table stays empty on \
                       both. Counting owned links here is what made a two-node setup report \
                       "1 entry in link table" when Python reports none.
                       """)
        XCTAssertEqual(bT.getLinkCount(), 0)
    }

    // MARK: - A relayed link is

    func testARelayedLinkAppearsInTheRelayLinkTableOnly() throws {
        let aT = Transport(), rT = Transport(), bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "lxmf", aspects: ["delivery"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)

        let aToR = HopInterface(name: "A→R"), rFromA = HopInterface(name: "R←A")
        wire(aToR, rFromA)
        aT.register(interface: aToR)
        rT.register(interface: rFromA)

        let rToB = HopInterface(name: "R→B"), bFromR = HopInterface(name: "B←R")
        wire(rToB, bFromR)
        rT.register(interface: rToB)
        bT.register(interface: bFromR)

        rT.restore(path: Transport.PathEntry(destinationHash: bDest.hash,
                                             nextHopInterface: rToB,
                                             hops: 1,
                                             lastHeard: Date(),
                                             identityHash: bId.hash),
                   forDestination: bDest.hash)
        // A relay validates the signature on every link-request proof it forwards, so it
        // needs the responder's identity. A real relay always has it: the announce that
        // taught it the path is the packet that carried the keys.
        rT.restore(identity: bId, forDestination: bDest.hash)

        let aE = expectation(description: "initiator"), bE = expectation(description: "responder")
        aT.onLinkEstablished = { _ in aE.fulfill() }
        bT.onLinkEstablished = { _ in bE.fulfill() }
        _ = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)

        XCTAssertEqual(rT.getLinkCount(), 1,
                       "the relay carries the link, so it holds the one link-table entry")
        XCTAssertEqual(aT.getLinkCount(), 0, "the initiator terminates it")
        XCTAssertEqual(bT.getLinkCount(), 0, "so does the responder")
    }

    // MARK: - The count follows the table, not the links dictionary

    func testTheCountTracksLinkTableEntriesAsTheyAreSwept() throws {
        let t = Transport()
        XCTAssertEqual(t.getLinkCount(), 0)

        let iface = HopInterface(name: "lo")
        t.register(interface: iface)
        t.restore(linkRoute: Transport.LinkRoute(linkID: Data(repeating: 0x01, count: 16),
                                                 initiatorSideInterface: iface,
                                                 responderSideInterface: iface,
                                                 initiatorSideInterfaceName: iface.name,
                                                 responderSideInterfaceName: iface.name,
                                                 destinationHash: Data(repeating: 0x02, count: 16),
                                                 lastHeard: Date()))
        XCTAssertEqual(t.getLinkCount(), 1,
                       "a restored link-table entry counts, even though this node holds no "
                       + "Link object for it—which is the whole distinction Python draws")
    }
}
