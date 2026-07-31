import XCTest
@testable import ReticulumSwift

/// `swift_devel/bugs/047` — a node ignores announces for destinations it owns.
///
/// Python computes `local_destination` from `destinations_map` and gates the **entire** announce
/// block on it being nil (`RNS/Transport.py:1767-1772`): path table, identity caching, announce
/// handlers and relay are all inside that `if`. It checks ownership a second time at the
/// path-table admission test (`:1806-1807`), which tells you how load-bearing it is.
///
/// This matters because a transport-enabled neighbour **reflects announces back to their
/// originator** by design — `Transport.outbound`'s broadcast loop (`:1197`) has no
/// receiving-interface exclusion, and the PATHFINDER_R retransmission re-sends with
/// `attached_interface = None` (`:604-637`). Every node hears its own announces come back. Python
/// drops them here; without this gate they are processed in full.
///
/// The symptom that surfaced it: a lone Swift LXMF propagation node, on a mesh with nobody else on
/// it, ended with exactly one peer — itself.
final class OwnAnnounceTests: XCTestCase {

    // MARK: - The gate

    func testAnAnnounceForAnOwnedDestinationReachesNoHandler() throws {
        let net = try makeReflectingPair()

        try net.reflectOwnAnnounce()

        XCTAssertTrue(net.handler.received.isEmpty,
                      """
                      a node handed its own announce to a registered announce handler. Python \
                      never gets here (Transport.py:1770). A handler that only reads is harmless; \
                      one that creates state is not — this is how an LXMF propagation node peers \
                      with itself, burning a peer slot, being dialled on every sync pass and being \
                      judged by rotation on an acceptance record it cannot accumulate.
                      """)
    }

    func testANodeLearnsNoPathToItself() throws {
        let net = try makeReflectingPair()

        try net.reflectOwnAnnounce()

        XCTAssertNil(net.owner.hopsTo(net.ownedHash),
                     """
                     the node installed a path-table entry for a destination it owns \
                     (Transport.py:1806-1807 excludes it explicitly). With one, it answers path \
                     requests for itself with a routed entry, and every local hop-count test — \
                     including LXMF's autopeer depth check — reads a distance to itself as if it \
                     were a remote node.
                     """)
    }

    func testAnAnnounceForADestinationTheNodeDoesNotOwnStillArrives() throws {
        let net = try makeReflectingPair()

        // Same wire path, same handler, one input changed: a destination the node does not own.
        // Without this, `received.isEmpty` above would pass against a transport that had simply
        // stopped dispatching announces at all.
        let strangerIdentity = Identity()
        let stranger = try Destination(identity: strangerIdentity, direction: .in, kind: .single,
                                       appName: "lxmf", aspects: ["propagation"])
        _ = try net.remote.announce(destination: stranger)

        XCTAssertEqual(net.handler.received.count, 1,
                       "the gate must drop the node's own announces only, not every announce")
        XCTAssertEqual(net.handler.received.first?.destinationHash, stranger.hash)
    }

    // MARK: - Harness

    private struct Network {
        let owner: Transport
        let remote: Transport
        let handler: RecordingHandler
        let ownedHash: Data
        let ownedOnRemote: Destination

        /// Deliver the owner an announce for the destination the owner has registered.
        ///
        /// Built from the same identity on the other transport, which is what a reflection off a
        /// transport-enabled neighbour amounts to: the same signed announce arriving back on an
        /// interface, indistinguishable on the wire from any other node's.
        func reflectOwnAnnounce() throws {
            _ = try remote.announce(destination: ownedOnRemote)
        }
    }

    private func makeReflectingPair() throws -> Network {
        let owner = Transport()
        let remote = Transport()
        let ownerInterface = LoopbackInterface(name: "owner")
        let remoteInterface = LoopbackInterface(name: "remote")
        ownerInterface.paired = remoteInterface
        remoteInterface.paired = ownerInterface
        owner.register(interface: ownerInterface)
        remote.register(interface: remoteInterface)
        retained.append(contentsOf: [owner, remote])

        let identity = Identity()
        let owned = try Destination(identity: identity, direction: .in, kind: .single,
                                    appName: "lxmf", aspects: ["propagation"])
        owner.register(destination: owned)

        let ownedOnRemote = try Destination(identity: identity, direction: .in, kind: .single,
                                            appName: "lxmf", aspects: ["propagation"])

        let handler = RecordingHandler()
        handler.aspectFilter = nil
        owner.register(announceHandler: handler)

        return Network(owner: owner, remote: remote, handler: handler,
                       ownedHash: owned.hash, ownedOnRemote: ownedOnRemote)
    }

    private var retained: [AnyObject] = []

    override func tearDown() {
        retained.removeAll()
        super.tearDown()
    }

    final class RecordingHandler: AnnounceHandler {
        var aspectFilter: String?
        var receivePathResponses: Bool = true
        var received: [(destinationHash: Data, identity: Identity, appData: Data?)] = []

        func receivedAnnounce(destinationHash: Data, identity: Identity, appData: Data?,
                              announcePacketHash: Data, isPathResponse: Bool) {
            received.append((destinationHash, identity, appData))
        }
    }

    final class LoopbackInterface: Interface {
        var name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }
}
