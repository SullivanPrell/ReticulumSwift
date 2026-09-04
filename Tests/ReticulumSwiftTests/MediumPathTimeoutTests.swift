import XCTest
@testable import ReticulumSwift

/// `Transport.medium_path_timeout()` and the `lowest_interface_bitrate` it reads, both new in
/// RNS 1.5.x (`Transport.py:3205`, `:568`).
///
/// The problem it solves: every path-resolution timeout in the `rn*` utilities was a fixed
/// number of seconds chosen for a fast link. On a LoRa-only node a single MTU takes several
/// seconds each way, so `rnpath`, `rncp`, `rnprobe` and `rnx` gave up while the request was
/// still in flight and reported the destination unreachable. The floor is now derived from
/// the slowest online interface instead of assumed.
///
/// The value is recomputed in `prioritizeInterfaces()`, which this port declared and then
/// never called—Python calls it at transport start and again on every jobs pass
/// (`Transport.py:524`, `:1151`). Without a caller the sort never ran either, so the
/// interface list was in registration order rather than bitrate order.
final class MediumPathTimeoutTests: XCTestCase {

    private final class Iface: Interface {
        var name: String
        var bitrate: Int
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String, bitrate: Int) { self.name = name; self.bitrate = bitrate }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}
    }

    /// `2*(MTU*8/bitrate) + DEFAULT_PER_HOP_TIMEOUT`—a full round trip for one MTU.
    private func expected(bitrate: Int) -> TimeInterval {
        2 * (Double(Constants.mtu) * 8 / Double(max(bitrate, Transport.minimumBitrate)))
            + Constants.defaultPerHopTimeout
    }

    // MARK: - The timeout itself

    /// Python returns a bare `0` when `lowest_interface_bitrate` is still `None`, *before*
    /// adding the per-hop constant (`Transport.py:3207`). Every caller wraps this in
    /// `max(timeout, …)`, so zero means "contribute nothing", not "time out immediately"—returning
    /// `DEFAULT_PER_HOP_TIMEOUT` here would silently raise the floor under every
    /// utility on a node whose interfaces haven't been prioritised yet.
    func testMediumPathTimeoutIsZeroBeforeAnyBitrateIsKnown() {
        XCTAssertEqual(Transport().mediumPathTimeout(), 0)
    }

    func testMediumPathTimeoutIsTwoMTURoundTripsPlusPerHop() {
        let t = Transport()
        t.register(interface: Iface(name: "lora", bitrate: 9600))
        t.prioritizeInterfaces()
        XCTAssertEqual(t.mediumPathTimeout(), expected(bitrate: 9600), accuracy: 1e-9)
    }

    /// `max(lowest_interface_bitrate, MINIMUM_BITRATE)` (`Transport.py:3208`). Without the
    /// clamp a misconfigured 1 bps interface yields an eight-thousand-second timeout, and a
    /// zero would divide by zero.
    func testABitrateBelowTheFloorIsClampedToMinimumBitrate() {
        let t = Transport()
        t.register(interface: Iface(name: "absurd", bitrate: 1))
        t.prioritizeInterfaces()
        XCTAssertEqual(t.mediumPathTimeout(), expected(bitrate: Transport.minimumBitrate), accuracy: 1e-9)
        XCTAssertEqual(t.lowestInterfaceBitrate, 1, "the clamp belongs to the timeout, not to the recorded bitrate")
    }

    /// The slowest link is what a path request has to survive, so the *minimum* is taken
    /// across interfaces even though the list is sorted the other way.
    func testTheSlowestOnlineInterfaceSetsTheTimeout() {
        let t = Transport()
        t.register(interface: Iface(name: "tcp", bitrate: 10_000_000))
        t.register(interface: Iface(name: "lora", bitrate: 1200))
        t.prioritizeInterfaces()
        XCTAssertEqual(t.lowestInterfaceBitrate, 1200)
        XCTAssertEqual(t.mediumPathTimeout(), expected(bitrate: 1200), accuracy: 1e-9)
    }

    // MARK: - Which interfaces count

    /// Python's generator filters on `if interface.online and interface.bitrate`, and
    /// `bitrate` is falsy for both `None` and `0`. An offline LoRa radio must not go on
    /// inflating every timeout on a node that's actually running over TCP.
    func testOfflineAndZeroBitrateInterfacesAreExcluded() {
        let t = Transport()
        let offline = Iface(name: "lora", bitrate: 1200)
        offline.isOnline = false
        t.register(interface: offline)
        t.register(interface: Iface(name: "unknown", bitrate: 0))
        t.register(interface: Iface(name: "tcp", bitrate: 10_000_000))
        t.prioritizeInterfaces()
        XCTAssertEqual(t.lowestInterfaceBitrate, 10_000_000)
    }

    /// Python's `min()` over an empty generator raises, and the `except` leaves the previous
    /// value in place rather than clearing it (`Transport.py:568-569`). Mirrored deliberately:
    /// a node whose interfaces have all dropped has no paths to resolve either, so the only
    /// observable difference would be utilities giving up *sooner* on a network that's down.
    func testTheLastKnownBitrateSurvivesEveryInterfaceGoingOffline() {
        let t = Transport()
        let iface = Iface(name: "lora", bitrate: 1200)
        t.register(interface: iface)
        t.prioritizeInterfaces()
        XCTAssertEqual(t.lowestInterfaceBitrate, 1200)

        iface.isOnline = false
        t.prioritizeInterfaces()
        XCTAssertEqual(t.lowestInterfaceBitrate, 1200, "a failed recompute must not clear the last known value")
    }

    // MARK: - The sort

    /// The ordering contract: fastest first, registration order among equals—Python's
    /// `list.sort` is stable, and this now runs on every jobs pass, so a reshuffle of
    /// same-bitrate interfaces would change announce emission order every five seconds.
    ///
    /// This pins the contract, not the comparator. Swift's `sort(by:)` is documented as *not*
    /// guaranteed stable, but today's implementation preserves order even at forty equal keys,
    /// so replacing the index-decorated comparator with a bare `>` doesn't make this fail.
    /// The comparator stays because the guarantee is the thing being relied on, and a future
    /// stdlib is free to withdraw the accident.
    func testEqualBitratesKeepRegistrationOrder() {
        let t = Transport()
        let names = (0..<40).map { "iface-\($0)" }
        for name in names { t.register(interface: Iface(name: name, bitrate: 9600)) }
        t.register(interface: Iface(name: "fast", bitrate: 1_000_000))
        for _ in 0..<5 {
            t.prioritizeInterfaces()
            XCTAssertEqual(t.interfaces.map(\.name), ["fast"] + names)
        }
    }

    // MARK: - The wiring

    /// The seam, not the value: `prioritizeInterfaces()` existed and was correct, and nothing
    /// in `Sources/` called it. Fails if the jobs loop stops refreshing the bitrate.
    func testTheJobsLoopRefreshesTheLowestBitrate() {
        let t = Transport()
        t.register(interface: Iface(name: "lora", bitrate: 1200))
        XCTAssertEqual(t.mediumPathTimeout(), 0, "nothing has prioritised yet")
        t.runJobs()
        XCTAssertEqual(t.mediumPathTimeout(), expected(bitrate: 1200), accuracy: 1e-9)
    }
}
