import XCTest
@testable import ReticulumSwift

/// Concurrency stress test for the `WeaveDevice.endpoints` lock added in the
/// 2026-07-19 hardening pass (the deferred "Weave device.endpoints prune"
/// follow-up).
///
/// The endpoint registry is written from the WDCL receive thread
/// (`endpointAlive` / `endpointVia`, reached via `incomingFrame`) and both read
/// and pruned from the periodic jobs thread (`WeaveInterface.peerJobs` →
/// `pruneEndpoints`). Those are *different* threads with no shared serial queue,
/// so — the Python reference survives only under the GIL — Swift needs an
/// explicit lock. Here we hammer all four operations (learn / route / prune /
/// snapshot-read) from many threads at once.
///
/// Without `WeaveDevice.endpointsLock` this races the backing `Dictionary` and
/// CRASHES ("Fatal error: Duplicate keys" / heap corruption); a lock-order
/// inversion or reentrant self-deadlock would make it TIME OUT. Passing proves
/// neither happens. Must also be clean under `swift test --sanitize=thread`
/// (0 data races) — the reads deliberately touch `WeaveEndpoint` fields, which
/// is safe because a record is never mutated in place once inserted.
final class WeaveConcurrencyStressTests: XCTestCase {

    func testEndpointRegistryConcurrentLearnPruneRead() {
        // No `rnsInterface` wired: isolates the device endpoint registry so the
        // race under test is purely `WeaveDevice.endpoints` (not the peer table).
        let dev        = WeaveDevice()
        let idPool     = 64      // small pool → heavy key overlap / contention
        let workers    = 8
        let iterations = 3000

        let done = expectation(description: "weave endpoint stress complete")
        DispatchQueue.global().async {
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                for i in 0..<iterations {
                    let n    = (w &+ i) % idPool
                    let epID = Data([UInt8(n)]) + Data(repeating: 0, count: 7)
                    switch (w &+ i) % 4 {
                    case 0:
                        dev.endpointAlive(endpointID: epID)              // insert / refresh
                    case 1:
                        dev.endpointVia(endpointID: epID,
                                        viaSwitchID: Data([UInt8(n), 0x02, 0x03, 0x04]))
                    case 2:
                        // Aggressive prune: everything already present is "stale"
                        // relative to a fresh `now`, so removals race the inserts
                        // happening on the other workers.
                        dev.pruneEndpoints(olderThan: 0, now: Date())
                    default:
                        // Snapshot + field reads. Safe because handed-out records
                        // are immutable after insertion (endpointAlive/endpointVia
                        // replace rather than mutate in place).
                        var acc = 0
                        for (_, ep) in dev.endpoints {
                            acc &+= ep.endpointAddr.count &+ (ep.viaSwitchID?.count ?? 0)
                        }
                        _ = acc
                    }
                }
            }
            done.fulfill()
        }

        // Generous timeout: a real deadlock never completes, so any pass here
        // means the lock graph is acyclic on these paths.
        wait(for: [done], timeout: 120)

        // Survived without crashing/deadlocking. The registry only ever holds
        // keys from the pool, and a final all-stale sweep must empty it.
        XCTAssertLessThanOrEqual(dev.endpoints.count, idPool)
        dev.pruneEndpoints(olderThan: 0, now: Date(timeIntervalSinceNow: 3600))
        XCTAssertTrue(dev.endpoints.isEmpty)
    }
}
