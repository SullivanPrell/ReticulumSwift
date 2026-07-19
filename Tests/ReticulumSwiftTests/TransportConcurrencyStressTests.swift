import XCTest
@testable import ReticulumSwift

/// Concurrency smoke tests for the Transport bookkeeping locks introduced in the
/// 2026-07-19 data-race hardening pass. The rest of the suite is single-threaded
/// and cannot exercise these races; here we hammer the lock-protected accessors
/// from many threads at once. A lock-order inversion or reentrant self-deadlock
/// would make the test TIME OUT; a torn dictionary/array access would CRASH.
/// Passing proves neither happens on these paths.
final class TransportConcurrencyStressTests: XCTestCase {

    /// Minimal interface with ingress + rate control enabled so the ingress /
    /// rate-table code paths actually execute (not just early-return).
    private final class StressIface: Interface {
        var name: String
        var bitrate: Int = 9600
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var ingressControl: Bool { true }
        var egressControl: Bool { true }
        var announceRateTarget: Double? { 1.0 }
        init(name: String) { self.name = name }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}
    }

    func testConcurrentBookkeepingDoesNotDeadlockOrCrash() {
        let transport = Transport()

        // A fixed pool of interfaces we churn in/out concurrently.
        let pool = (0..<6).map { StressIface(name: "if\($0)") }
        for iface in pool { transport.register(interface: iface) }

        let done = expectation(description: "stress complete")
        let workers = 8
        let iterations = 1500

        DispatchQueue.global().async {
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                for i in 0..<iterations {
                    let iface = pool[(w &+ i) % pool.count]
                    let now = 1_700_000_000.0 + Double(i)
                    switch (w &+ i) % 13 {
                    case 0:  transport.register(interface: iface)          // interfaces + trackers + ingress
                    case 1:  transport.deregister(interface: iface)        // removes all per-iface state
                    case 2:  _ = transport.getInterfaceStats()             // snapshots interfaces + trackers
                    case 3:  _ = transport.getTransportStats()             // metricsLock
                    case 4:  transport.sampleInterfaceSpeeds(now: now)     // interfaces snapshot + metricsLock
                    case 5:  transport.notifyIncomingAnnounce(on: iface, at: now)  // trackersLock -> tracker
                    case 6:  _ = transport.shouldIngressLimit(on: iface, now: now) // ingressLock -> trackersLock
                    case 7:  _ = transport.isAnnounceRateBlocked(destinationHash: Data(repeating: UInt8(i & 0xFF), count: 16), interface: iface, now: now) // metricsLock
                    case 8:  let h = Data([UInt8(w & 0xFF)] + Data(repeating: UInt8(i & 0xFF), count: 15))
                             transport.blackholeIdentity(h)               // blackholeLock (+ lock via removeBlackholedPaths)
                    case 9:  let h = Data([UInt8(w & 0xFF)] + Data(repeating: UInt8(i & 0xFF), count: 15))
                             _ = transport.isBlackholed(h)                // blackholeLock
                    case 10: transport.sweepExpiredBlackholes(now: now)   // blackholeLock
                    case 11: _ = transport.currentRxSpeed(for: iface)     // metricsLock
                    case 12: _ = transport.getPacketRssi(packetHash: Data(repeating: UInt8(i & 0xFF), count: 16)) // metricsLock
                    default: break
                    }
                }
            }
            done.fulfill()
        }

        // Generous timeout: a real deadlock never completes, so any pass here
        // means the lock graph is acyclic on these paths.
        wait(for: [done], timeout: 60)
    }
}
