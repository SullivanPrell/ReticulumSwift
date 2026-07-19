import XCTest
@testable import ReticulumSwift

/// Concurrency stress tests for the `Link.stateLock` introduced in the 2026-07-19
/// deferred data-race hardening pass (L1 + L2). The rest of the Link suite is
/// single-threaded and cannot exercise the watchdog / receive-thread / app-thread
/// races on the session state machine, the traffic counters/timestamps, the
/// `token`/`derivedKey`, `pendingRequests`, or the resource queues.
///
/// A lock-order inversion or reentrant self-deadlock (holding `stateLock` across a
/// `transport.*` call, a callback, or `close`/`teardown`/`send`) would make these
/// tests TIME OUT; a torn read of `token`/`derivedKey` or a `pendingRequests` /
/// resource-array corruption would CRASH. Passing under ThreadSanitizer
/// (`swift test -Xswiftc -sanitize=thread --filter LinkConcurrencyStressTests`)
/// proves neither happens.
final class LinkConcurrencyStressTests: XCTestCase {

    private final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    private var aT: Transport!; private var bT: Transport!

    private func establishLink() throws -> (Link, Link) {
        aT = Transport(); bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["linkconc"])
        // A request handler so some requests get answered (and the rest time out).
        bDest.registerRequestHandler(path: "/echo", allow: .all) { _, data, _, _, _ in
            return data ?? Data([0x01])
        }
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)
        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aT.onLinkEstablished = { _ in aE.fulfill() }; bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aLink, bLink)
    }

    private func hammerAccessors(_ link: Link) {
        _ = link.status
        _ = link.getStatus()
        _ = link.getRtt()
        _ = link.getMtu()
        _ = link.getMdu()
        _ = link.getAge()
        _ = link.noInboundFor()
        _ = link.noOutboundFor()
        _ = link.noDataFor()
        _ = link.inactiveFor()
        _ = link.getTeardownReason()
        _ = link.getRemoteIdentity()
        _ = link.getExpectedRate()
        _ = link.getEstablishmentRate()
        _ = link.tx; _ = link.rx; _ = link.txBytes; _ = link.rxBytes
        _ = link.getLastResourceWindow()
    }

    // MARK: - Live-traffic surface (send / receive / request / channel / accessors)

    func testConcurrentLinkTrafficDoesNotCrashOrRace() throws {
        let (aLink, bLink) = try establishLink()

        let done = expectation(description: "traffic stress")
        let workers = 8
        let iterations = 800

        DispatchQueue.global().async {
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                for i in 0..<iterations {
                    switch (w &+ i) % 8 {
                    case 0: try? aLink.send(Data(repeating: UInt8(i & 0xFF), count: 24)) // encrypt + transport.send + counters
                    case 1: self.hammerAccessors(aLink)
                    case 2: self.hammerAccessors(bLink)
                    case 3: aLink.hadOutbound()
                    case 4: _ = aLink.getChannel()                                        // lazy channel race
                    case 5: try? aLink.sendKeepalive()
                    case 6: _ = try? aLink.request(path: "/echo",
                                                   data: Data([UInt8(i & 0xFF)]),
                                                   timeout: 0.02)                         // receipts pile + evict
                    default: self.hammerAccessors(aLink)
                    }
                }
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 60)

        // Let outstanding request timeouts fire and evict, then confirm the pending
        // table drained (growth-eviction regression guard).
        let drained = expectation(description: "pendingRequests drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            aLink.stateLock.lock(); let count = aLink.pendingRequests.count; aLink.stateLock.unlock()
            XCTAssertEqual(count, 0, "pendingRequests should drain to empty after timeouts/evictions")
            drained.fulfill()
        }
        wait(for: [drained], timeout: 5)
    }

    // MARK: - Terminal-transition surface (teardown / close / accessors)

    func testConcurrentTeardownDoesNotCrashOrRace() throws {
        let (aLink, _) = try establishLink()

        let done = expectation(description: "teardown stress")
        let workers = 8
        let iterations = 400

        DispatchQueue.global().async {
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                for i in 0..<iterations {
                    switch (w &+ i) % 5 {
                    case 0: self.hammerAccessors(aLink)
                    case 1: try? aLink.send(Data([UInt8(i & 0xFF)]))
                    case 2: _ = aLink.getChannel()
                    case 3: if (w &+ i) % 37 == 0 { try? aLink.teardown() } // idempotent terminal
                    default: aLink.close()                                  // idempotent terminal
                    }
                }
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 60)
        XCTAssertTrue(aLink.status == .closed || aLink.status == .failed || aLink.status == .stale,
                      "link should be terminal after concurrent teardown/close")
    }
}
