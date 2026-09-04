import XCTest
@testable import ReticulumSwift

/// A transport node that can't answer a path request from its own tables amplifies it: one
/// inbound request becomes one outbound request per other interface. RNS 1.5.x added two tables
/// that bound the amplification and pay for it with a compensating retransmit.
///
/// `inflight_path_requests` marks a destination as already under search, so concurrent requests
/// for it batch onto the first search instead of each starting their own
/// (`Transport.py:1862-1886`). `discovery_path_requests` records who joined that batch, so the
/// announce that eventually resolves the search replays to each of them as a path response
/// (`Transport.py:2433-2455`).
///
/// The two halves belong together. Batching alone is strictly worse than no batching at all: it
/// drops the duplicate requests and nothing ever answers them.
final class DiscoveryPathRequestTests: XCTestCase {

    // MARK: - Fixtures

    private final class PRInterface: Interface {
        var name: String
        var bitrate: Int
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        var mode: InterfaceMode = .full
        var recursivePrs: Bool = false
        var ingressControl: Bool = true
        init(name: String, bitrate: Int = 1_000_000) {
            self.name = name
            self.bitrate = bitrate
        }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    /// `target || requestor transport id || tag`—the three-field body shape
    /// `path_request_handler` parses (`Transport.py:3391-3402`).
    private func request(for target: Data, on t: Transport, tag: Data) -> Packet {
        Packet(destinationType: .plain, packetType: .data,
               destinationHash: Transport.pathRequestDestinationHash,
               data: target + t.transportInstanceID + tag)
    }

    private func tag(_ byte: UInt8) -> Data { Data(repeating: byte, count: 16) }

    private func forwardedRequests(_ iface: PRInterface) -> [Packet] {
        iface.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
    }

    private func pathResponses(_ iface: PRInterface) -> [Packet] {
        iface.sent.filter { $0.packetType == .announce && $0.context == .pathResponse }
    }

    /// Fill the incoming path-request deque inside the last half-second of *real* time, so the
    /// limiter—which reads the wall clock—observes a burst far past its threshold.
    private func floodPathRequests(_ t: Transport, on iface: any Interface) {
        let start = Date().timeIntervalSince1970 - 0.5
        for i in 0 ..< InterfaceFreqTracker.maxSamples {
            t.notifyIncomingPathRequest(on: iface, at: start + Double(i) * 0.01)
        }
    }

    /// The announce-side equivalent, which arms the exemption's control case.
    private func floodAnnounces(_ t: Transport, on iface: any Interface) {
        let start = Date().timeIntervalSince1970 - 0.5
        for i in 0 ..< 60 {
            t.notifyIncomingAnnounce(on: iface, at: start + Double(i) * 0.008)
        }
    }

    private func makeNode(bitrate: Int = 1_000_000) -> (Transport, PRInterface, PRInterface) {
        let t = Transport()
        t.transportEnabled = true
        let ingress = PRInterface(name: "ingress", bitrate: bitrate)
        ingress.recursivePrs = true
        let egress = PRInterface(name: "egress", bitrate: bitrate)
        t.register(interface: ingress)
        t.register(interface: egress)
        t.prioritizeInterfaces()
        return (t, ingress, egress)
    }

    private func remoteDestination() throws -> Destination {
        try Destination(identity: Identity(), direction: .in, kind: .single,
                        appName: "test", aspects: ["remote"])
    }

    // MARK: - The in-flight marker

    func testAFirstPathRequestRegistersAnInFlightMarker() {
        let (t, ingress, egress) = makeNode()
        let target = Data(repeating: 0x77, count: 16)

        ingress.inboundHandler?(request(for: target, on: t, tag: tag(0x01)), ingress)

        XCTAssertEqual(forwardedRequests(egress).count, 1,
                       "the control: an unbatched request still fans out")
        XCTAssertNotNil(t.inflightPathRequestTimestamp(for: target),
                        """
                        `Transport.inflight_path_requests[destination_hash] = time.time()` \
                        (Transport.py:1868) — registered eagerly, before the search starts, \
                        precisely so a duplicate arriving mid-search sees it
                        """)
    }

    func testASecondRequestForTheSameDestinationDoesNotFanOutAgain() {
        let (t, ingress, egress) = makeNode()
        let second = PRInterface(name: "second")
        second.recursivePrs = true
        t.register(interface: second)
        let target = Data(repeating: 0x77, count: 16)

        ingress.inboundHandler?(request(for: target, on: t, tag: tag(0x01)), ingress)
        let afterFirst = forwardedRequests(egress).count
        second.inboundHandler?(request(for: target, on: t, tag: tag(0x02)), second)

        XCTAssertEqual(afterFirst, 1, "the first request must fan out")
        XCTAssertEqual(forwardedRequests(egress).count, 1,
                       """
                       a second request for a destination already being searched for batches \
                       onto the existing search (Transport.py:1871-1884) rather than starting \
                       a second identical fan-out
                       """)
    }

    func testABatchedRequestRecordsItsRequestingInterface() {
        let (t, ingress, _) = makeNode()
        let second = PRInterface(name: "second")
        second.recursivePrs = true
        t.register(interface: second)
        let target = Data(repeating: 0x77, count: 16)

        ingress.inboundHandler?(request(for: target, on: t, tag: tag(0x01)), ingress)
        second.inboundHandler?(request(for: target, on: t, tag: tag(0x02)), second)

        let entry = t.discoveryPathRequest(for: target)
        XCTAssertNotNil(entry)
        XCTAssertTrue(entry?.requestingInterfaces.contains(where: { $0 === ingress }) == true,
                      "the interface that started the search is a requestor too")
        XCTAssertTrue(entry?.requestingInterfaces.contains(where: { $0 === second }) == true,
                      """
                      `requesting_interfaces.append(packet.receiving_interface)` \
                      (Transport.py:1875) — a batched requestor must be recorded, or the \
                      answer never reaches it
                      """)
    }

    func testTheSameInterfaceIsNotRecordedTwice() {
        let (t, ingress, _) = makeNode()
        let second = PRInterface(name: "second")
        second.recursivePrs = true
        t.register(interface: second)
        let target = Data(repeating: 0x77, count: 16)

        ingress.inboundHandler?(request(for: target, on: t, tag: tag(0x01)), ingress)
        second.inboundHandler?(request(for: target, on: t, tag: tag(0x02)), second)
        second.inboundHandler?(request(for: target, on: t, tag: tag(0x03)), second)

        let recorded = t.discoveryPathRequest(for: target)?.requestingInterfaces ?? []
        XCTAssertEqual(recorded.filter { $0 === second }.count, 1,
                       """
                       `if not packet.receiving_interface in ...["requesting_interfaces"]` \
                       (Transport.py:1874) — a peer that keeps asking must not multiply the \
                       replay it eventually gets
                       """)
    }

    func testAnIngressLimitedDuplicateIsNotBatched() {
        let (t, ingress, _) = makeNode()
        let noisy = PRInterface(name: "noisy")
        noisy.recursivePrs = true
        t.register(interface: noisy)
        let target = Data(repeating: 0x77, count: 16)

        ingress.inboundHandler?(request(for: target, on: t, tag: tag(0x01)), ingress)
        floodPathRequests(t, on: noisy)
        XCTAssertTrue(t.shouldIngressLimitPR(on: noisy), "the fixture must arm the limiter")
        noisy.inboundHandler?(request(for: target, on: t, tag: tag(0x02)), noisy)

        let recorded = t.discoveryPathRequest(for: target)?.requestingInterfaces ?? []
        XCTAssertFalse(recorded.contains(where: { $0 === noisy }),
                       """
                       `if not traffic_class == Transport.TC_INGRESS_LIMITED` \
                       (Transport.py:1870) — a flooding peer's duplicates are dropped outright, \
                       not enrolled for a replay each
                       """)
    }

    // MARK: - Resolving the marker

    func testAnsweringFromALocalDestinationClearsTheMarker() throws {
        let (t, ingress, _) = makeNode()
        let local = try Destination(identity: Identity(), direction: .in, kind: .single,
                                    appName: "test", aspects: ["local"])
        t.register(destination: local)

        ingress.inboundHandler?(request(for: local.hash, on: t, tag: tag(0x01)), ingress)

        XCTAssertNil(t.inflightPathRequestTimestamp(for: local.hash),
                     """
                     `if answered: ... inflight_path_requests.pop(destination_hash)` \
                     (Transport.py:3595-3599) — an answered request is not in flight, and \
                     leaving the marker would swallow every later request for the same \
                     destination
                     """)
    }

    func testASecondRequestForALocalDestinationIsStillAnswered() throws {
        let (t, ingress, _) = makeNode()
        let local = try Destination(identity: Identity(), direction: .in, kind: .single,
                                    appName: "test", aspects: ["local"])
        t.register(destination: local)

        ingress.inboundHandler?(request(for: local.hash, on: t, tag: tag(0x01)), ingress)
        ingress.inboundHandler?(request(for: local.hash, on: t, tag: tag(0x02)), ingress)

        XCTAssertEqual(pathResponses(ingress).count, 2,
                       "the consequence of clearing the marker: the node keeps answering")
    }

    func testAnsweringFromAKnownPathClearsTheMarker() throws {
        let (t, ingress, egress) = makeNode()
        let dest = try remoteDestination()
        egress.inboundHandler?(try Announce.make(for: dest), egress)
        XCTAssertTrue(t.hasPath(to: dest.hash), "the announce must install a path")

        ingress.inboundHandler?(request(for: dest.hash, on: t, tag: tag(0x01)), ingress)

        XCTAssertEqual(pathResponses(ingress).count, 1, "the control: the request is answered")
        XCTAssertNil(t.inflightPathRequestTimestamp(for: dest.hash),
                     "`answered = True` is set in the known-path branch too (Transport.py:3463)")
    }

    // MARK: - The engaged gate

    func testTheRecursiveBranchMarksItsEntryEngaged() {
        let (t, ingress, _) = makeNode()
        let target = Data(repeating: 0x77, count: 16)

        ingress.inboundHandler?(request(for: target, on: t, tag: tag(0x01)), ingress)

        XCTAssertEqual(t.discoveryPathRequest(for: target)?.engaged, true,
                       """
                       `pr_entry = { ..., "engaged": True }` (Transport.py:3561) — the flag \
                       distinguishes an entry this node is actively searching on from one that \
                       only records batched requestors
                       """)
    }

    func testAnEngagedEntrySuppressesASecondFanOut() {
        // On a slow network the discovery entry outlives the 45 s in-flight gate, so a fresh
        // request can reach the recursive branch while the earlier search is still running.
        // `engaged` is what stops it starting a duplicate search.
        let (t, ingress, egress) = makeNode(bitrate: Transport.minimumBitrate)
        let target = Data(repeating: 0x77, count: 16)
        let now = Date().timeIntervalSince1970

        ingress.inboundHandler?(request(for: target, on: t, tag: tag(0x01)), ingress)
        t.sweepPathRequestTables(now: now + Transport.pathRequestGateTimeout + 1)
        XCTAssertNil(t.inflightPathRequestTimestamp(for: target),
                     "the fixture must expire the in-flight marker")
        XCTAssertEqual(t.discoveryPathRequest(for: target)?.engaged, true,
                       "…while leaving the longer-lived discovery entry standing")

        ingress.inboundHandler?(request(for: target, on: t, tag: tag(0x02)), ingress)

        XCTAssertEqual(forwardedRequests(egress).count, 1,
                       """
                       `if discovery_path_request_exists and path_request_engaged:` \
                       (Transport.py:3541) — the second request logs and returns instead of \
                       fanning out again
                       """)
    }

    func testABatchOnlyEntryDoesNotSuppressARealSearch() {
        // The mirror image: an entry from the batching branch carries `engaged: False`
        // (Transport.py:1881), so nothing must read it as a search already under way.
        let (t, ingress, egress) = makeNode(bitrate: Transport.minimumBitrate)
        let second = PRInterface(name: "second")
        second.recursivePrs = true
        t.register(interface: second)
        t.prioritizeInterfaces()
        let target = Data(repeating: 0x77, count: 16)
        let now = Date().timeIntervalSince1970

        // Drive the batching branch without ever reaching the recursive one, by holding the
        // in-flight marker in place while the entry forms.
        t.registerInflightPathRequest(target, at: now)
        second.inboundHandler?(request(for: target, on: t, tag: tag(0x02)), second)
        XCTAssertEqual(t.discoveryPathRequest(for: target)?.engaged, false,
                       "the fixture must produce a batch-only entry")

        t.sweepPathRequestTables(now: now + Transport.pathRequestGateTimeout + 1)
        ingress.inboundHandler?(request(for: target, on: t, tag: tag(0x01)), ingress)

        XCTAssertEqual(forwardedRequests(egress).count, 1,
                       "a batch-only entry records requestors; it does not claim a search")
        XCTAssertEqual(t.discoveryPathRequest(for: target)?.engaged, true,
                       "and the search that does start takes the entry over")
        XCTAssertTrue(t.discoveryPathRequest(for: target)?
                        .requestingInterfaces.contains(where: { $0 === second }) == true,
                      """
                      `existing_requesting_interfaces = ...["requesting_interfaces"]` \
                      (Transport.py:3566) — the peers batched before the search started keep \
                      their claim on its answer
                      """)
    }

    // MARK: - Expiry

    func testTheInFlightMarkerExpiresAtTheGateTimeout() {
        let t = Transport()
        let target = Data(repeating: 0x77, count: 16)
        let now: TimeInterval = 1000
        t.registerInflightPathRequest(target, at: now)

        t.sweepPathRequestTables(now: now + Transport.pathRequestGateTimeout - 1)
        XCTAssertNotNil(t.inflightPathRequestTimestamp(for: target), "not stale yet")

        t.sweepPathRequestTables(now: now + Transport.pathRequestGateTimeout + 1)
        XCTAssertNil(t.inflightPathRequestTimestamp(for: target),
                     """
                     `if time.time() > snapshot[destination_hash] + PATH_REQUEST_GATE_TIMEOUT` \
                     (Transport.py:997) — without the sweep a search that is never answered \
                     blocks every later request for that destination forever
                     """)
    }

    func testTheDiscoveryEntryExpiresAtItsOwnTimeout() {
        let (t, ingress, _) = makeNode()
        let target = Data(repeating: 0x77, count: 16)
        let now = Date().timeIntervalSince1970

        ingress.inboundHandler?(request(for: target, on: t, tag: tag(0x01)), ingress)
        let timeout = try? XCTUnwrap(t.discoveryPathRequest(for: target)?.timeout)
        XCTAssertEqual(timeout ?? 0, now + max(Transport.pathRequestTimeout, t.mediumPathTimeout()),
                       accuracy: 1.0,
                       """
                       `discovery_timeout = max(PATH_REQUEST_TIMEOUT, medium_path_timeout())` \
                       (Transport.py:3556) — the wait must cover a full round trip on the \
                       slowest link, or the answer arrives after the entry is gone
                       """)

        t.sweepPathRequestTables(now: (timeout ?? 0) + 1)
        XCTAssertNil(t.discoveryPathRequest(for: target),
                     "`if time.time() > entry[\"timeout\"]` (Transport.py:1010)")
    }

    // MARK: - The replay

    func testAMatchingAnnounceIsReplayedToEveryRequestingInterface() throws {
        let (t, ingress, egress) = makeNode()
        let second = PRInterface(name: "second")
        second.recursivePrs = true
        t.register(interface: second)
        let dest = try remoteDestination()

        ingress.inboundHandler?(request(for: dest.hash, on: t, tag: tag(0x01)), ingress)
        second.inboundHandler?(request(for: dest.hash, on: t, tag: tag(0x02)), second)
        ingress.sent.removeAll()
        second.sent.removeAll()

        egress.inboundHandler?(try Announce.make(for: dest), egress)

        XCTAssertEqual(pathResponses(ingress).count, 1,
                       """
                       "Got matching announce, answering waiting discovery path request" \
                       (Transport.py:2440) — this replay is what pays for the batching; \
                       without it the batched requests are simply lost
                       """)
        XCTAssertEqual(pathResponses(second).count, 1,
                       "every recorded requestor is answered, not just the first")
    }

    func testTheReplayIsAPathResponseFromThisTransportInstance() throws {
        let (t, ingress, egress) = makeNode()
        let dest = try remoteDestination()

        ingress.inboundHandler?(request(for: dest.hash, on: t, tag: tag(0x01)), ingress)
        ingress.sent.removeAll()
        let announce = try Announce.make(for: dest)
        egress.inboundHandler?(announce, egress)

        let replay = try XCTUnwrap(pathResponses(ingress).first)
        XCTAssertEqual(replay.headerType, .type2,
                       "`header_type = RNS.Packet.HEADER_2` (Transport.py:2452)")
        XCTAssertEqual(replay.transportType, .transport,
                       "`transport_type = Transport.TRANSPORT` (Transport.py:2452)")
        XCTAssertEqual(replay.transportID, t.transportInstanceID,
                       """
                       `transport_id = Transport.identity.hash` (Transport.py:2452) — the \
                       requestor must address its traffic to this node, which is the one that \
                       actually knows the route
                       """)
        XCTAssertEqual(replay.destinationHash, dest.hash)
    }

    func testTheReplayCarriesTheHopCountTheRequestorMustStore() throws {
        let (t, ingress, egress) = makeNode()
        let dest = try remoteDestination()

        ingress.inboundHandler?(request(for: dest.hash, on: t, tag: tag(0x01)), ingress)
        ingress.sent.removeAll()
        var announce = try Announce.make(for: dest)
        announce.hops = 2
        egress.inboundHandler?(announce, egress)

        let replay = try XCTUnwrap(pathResponses(ingress).first)
        XCTAssertEqual(replay.hops, 3,
                       """
                       `new_announce.hops = packet.hops` (Transport.py:2454), where Python's \
                       `packet.hops` has already been incremented on arrival \
                       (Transport.py:1800). This port does no inbound increment, so the same \
                       wire value is one more than the hop count it stored — the same \
                       adjustment the known-path answer makes with `entry.hops &+ 1`
                       """)
    }

    func testTheEntryIsConsumedBySingleReplay() throws {
        let (t, ingress, egress) = makeNode()
        let dest = try remoteDestination()

        ingress.inboundHandler?(request(for: dest.hash, on: t, tag: tag(0x01)), ingress)
        egress.inboundHandler?(try Announce.make(for: dest), egress)
        XCTAssertNil(t.discoveryPathRequest(for: dest.hash),
                     "`discovery_path_requests.pop(...)` (Transport.py:2436) — pop, not read")
        ingress.sent.removeAll()

        egress.inboundHandler?(try Announce.make(for: dest), egress)
        XCTAssertTrue(pathResponses(ingress).isEmpty,
                      "a later announce for the same destination is not replayed again")
    }

    func testAMatchingAnnounceAlsoClearsTheInFlightMarker() throws {
        let (t, ingress, egress) = makeNode()
        let dest = try remoteDestination()

        ingress.inboundHandler?(request(for: dest.hash, on: t, tag: tag(0x01)), ingress)
        XCTAssertNotNil(t.inflightPathRequestTimestamp(for: dest.hash), "the search is in flight")

        egress.inboundHandler?(try Announce.make(for: dest), egress)

        XCTAssertNil(t.inflightPathRequestTimestamp(for: dest.hash),
                     """
                     `# Resolve potential in-flight path requests` (Transport.py:2478-2481) — \
                     the search is over, so the next request for this destination must be free \
                     to start its own
                     """)
    }

    func testAnAnnounceThePathTableDeclinesLeavesTheSearchOutstanding() throws {
        // Upstream nests the release inside `if should_add:` (`Transport.py:2298`, `:2478`).
        // Only an announce this node learned from ends a search; releasing the marker for one
        // the freshness ladder threw away would let the next duplicate request start a second
        // fan-out while the first is still outstanding.
        let (t, _, egress) = makeNode()
        let dest = try remoteDestination()
        let now = Date().timeIntervalSince1970

        egress.inboundHandler?(try Announce.make(for: dest, timestamp: now), egress)
        XCTAssertTrue(t.hasPath(to: dest.hash), "the fixture must install a path to decline from")
        t.registerInflightPathRequest(dest.hash, at: now)

        var stale = try Announce.make(for: dest, timestamp: now - 3600)
        stale.hops = 3
        egress.inboundHandler?(stale, egress)

        XCTAssertEqual(t.paths[dest.hash]?.hops, 0, "the fixture must produce a declined announce")
        XCTAssertNotNil(t.inflightPathRequestTimestamp(for: dest.hash),
                        "a declined announce is not an answer, so the search stays outstanding")
    }

    // MARK: - The ingress-limit exemption

    func testAWaitingDiscoveryRequestExemptsItsAnnounceFromIngressLimiting() throws {
        let (t, ingress, egress) = makeNode()
        let dest = try remoteDestination()

        ingress.inboundHandler?(request(for: dest.hash, on: t, tag: tag(0x01)), ingress)
        floodAnnounces(t, on: egress)
        egress.inboundHandler?(try Announce.make(for: dest), egress)

        XCTAssertTrue(t.hasPath(to: dest.hash),
                      """
                      `if packet.destination_hash in ... discovery_path_requests: pass` \
                      (Transport.py:1819) — this node asked the network for exactly this \
                      destination, so holding the answer behind the burst limiter would strand \
                      the requestors it is holding open for
                      """)
        XCTAssertEqual(pathResponses(ingress).count, 1, "and the replay goes out")
    }

    func testAnUnrequestedAnnounceIsStillIngressLimited() throws {
        // The control for the preceding exemption: with no waiting request the limiter bites.
        let (t, _, egress) = makeNode()
        let dest = try remoteDestination()

        floodAnnounces(t, on: egress)
        egress.inboundHandler?(try Announce.make(for: dest), egress)

        XCTAssertFalse(t.hasPath(to: dest.hash),
                       "an unknown destination arriving in a burst is held, not installed")
    }
}
