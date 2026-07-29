import XCTest
import Network
@testable import ReticulumSwift

/// TCP keepalive on the dialing interfaces.
///
/// Python sets `SO_KEEPALIVE` plus the probe timers on every TCP client socket it opens
/// (`TCPInterface.set_timeouts_osx` / `set_timeouts_linux`, `BackboneInterface:655`).
/// ReticulumSwift set none: `NWConnection(to:using: .tcp)` takes Network.framework's
/// defaults, which have keepalive **off**.
///
/// Without it a connection whose peer vanished without sending FIN — a laptop that slept,
/// a NAT that dropped the mapping, a peer that was hard-killed — stays `.ready` forever.
/// No event ever fires, so the interface reports "Up", silently discards everything sent
/// through it, and the reconnect logic added for `bugs/013` never gets a chance to run:
/// there is nothing to trigger it. Keepalive is what turns a half-open connection into a
/// failure the interface can react to.
///
/// Reported as "RetiOS doesn't reconnect to the mesh after the laptop sleeps".
final class TCPKeepaliveTests: XCTestCase {

    /// Whether this OS reads back a TCP option that was set before the options object was
    /// handed to `NWParameters`. It does not on macOS 14: `defaultProtocolStack`
    /// `.transportProtocol` returns a *different* `NWProtocolTCP.Options` instance than the
    /// one passed in — `===` is false on every OS tested — and on 14 that re-wrapped
    /// instance reports framework defaults instead of the configured values.
    ///
    /// Probed with a control value rather than gated on an OS version, because the thing
    /// that matters is whether the readback can be trusted, not which OS is running.
    private var readbackIsTrustworthy: Bool {
        let control = NWProtocolTCP.Options()
        control.keepaliveIdle = 7
        let stack = NWParameters(tls: nil, tcp: control).defaultProtocolStack
        return (stack.transportProtocol as? NWProtocolTCP.Options)?.keepaliveIdle == 7
    }

    /// Python `TCPClientInterface`: `TCP_PROBE_AFTER = 5`, `TCP_PROBE_INTERVAL = 2`,
    /// `TCP_PROBES = 12`, `TCP_USER_TIMEOUT = 24` (`TCPInterface.py:83-86`).
    ///
    /// Asserted on the object the interface constructs and hands to Network.framework, which
    /// is the only place these values can be read back reliably — see
    /// ``TCPClientInterface/tcpOptions()``.
    func testClientOptionsCarryPythonsKeepaliveTimers() {
        let options = TCPClientInterface.tcpOptions()
        XCTAssertTrue(options.enableKeepalive, "keepalive must be on, as in Python")
        XCTAssertEqual(options.keepaliveIdle, 5)
        XCTAssertEqual(options.keepaliveInterval, 2)
        XCTAssertEqual(options.keepaliveCount, 12)
        XCTAssertEqual(options.connectionDropTime, 24)
    }

    /// Python sets `TCP_NODELAY` on every TCP socket it opens, on both platforms
    /// (`TCPInterface.py:148`, `:239`). RNS packets are small and latency-sensitive;
    /// Nagle would coalesce them behind the 40 ms delayed-ACK timer.
    func testClientOptionsDisableNagle() {
        XCTAssertTrue(TCPClientInterface.tcpOptions().noDelay)
    }

    /// The backbone client dials over the same networks and fails the same way
    /// (`BackboneInterface.py:626-627`, `:655-660`).
    func testBackboneOptionsCarryTheSameTimers() {
        let options = BackboneInterface.tcpOptions()
        XCTAssertTrue(options.enableKeepalive)
        XCTAssertEqual(options.keepaliveIdle, 5)
        XCTAssertEqual(options.keepaliveInterval, 2)
        XCTAssertEqual(options.keepaliveCount, 12)
        XCTAssertEqual(options.connectionDropTime, 24)
        XCTAssertTrue(options.noDelay)
    }

    /// The parameters a dial is built from must carry a TCP stack at all — true on every OS,
    /// and the part of ``TCPClientInterface/tcpParameters`` worth pinning: it would break if
    /// the initializer were ever changed to drop the options.
    func testParametersCarryATCPStack() throws {
        _ = try XCTUnwrap(
            TCPClientInterface.tcpParameters.defaultProtocolStack.transportProtocol
                as? NWProtocolTCP.Options,
            "expected a TCP transport protocol in the stack")
    }

    /// Where the platform's readback can be trusted, verify the values actually survive the
    /// trip through `NWParameters` rather than only asserting what we set. This is the leg
    /// that cannot run on macOS 14 — and the reason it is probed rather than skipped by OS
    /// version is that a future OS regaining or losing the readback should change what runs
    /// here without anyone editing an availability check.
    func testValuesSurviveTheTripThroughParametersWhereReadableAtAll() throws {
        try XCTSkipUnless(readbackIsTrustworthy,
                          "this OS reports framework defaults when a TCP option is read back "
                          + "through NWParameters.defaultProtocolStack")
        let options = try XCTUnwrap(
            TCPClientInterface.tcpParameters.defaultProtocolStack.transportProtocol
                as? NWProtocolTCP.Options)
        XCTAssertTrue(options.enableKeepalive)
        XCTAssertEqual(options.keepaliveIdle, 5)
        XCTAssertEqual(options.keepaliveInterval, 2)
        XCTAssertEqual(options.keepaliveCount, 12)
        XCTAssertEqual(options.connectionDropTime, 24)
        XCTAssertTrue(options.noDelay)
    }

    /// Every dial must get its own options object. `NWParameters` is a reference type, so
    /// handing the same instance to two connections lets Network.framework mutate shared
    /// state — and a `NWParameters` already used by a live connection cannot be reused.
    func testEachDialGetsFreshParameters() {
        XCTAssertFalse(TCPClientInterface.tcpParameters === TCPClientInterface.tcpParameters)
    }

    /// End to end: a real connection carrying these parameters still speaks to a peer.
    /// Keepalive settings are easy to get wrong in a way that makes the connection fail to
    /// establish at all, which no amount of property assertion would catch.
    func testAConnectionWithTheseParametersStillWorks() throws {
        // A concrete port rather than "any": before the listener reaches `.ready`,
        // `listener.port` reports the *requested* port, so asking for 0 reads back 0 and
        // there is no way to tell "not bound yet" from "bound to port 0".
        var bound: (listener: NWListener, port: UInt16)?
        for _ in 0..<16 {
            let candidate = UInt16.random(in: 41_000...48_000)
            guard let nwPort = NWEndpoint.Port(rawValue: candidate) else { continue }
            if let l = try? NWListener(using: TCPClientInterface.tcpParameters, on: nwPort) {
                bound = (l, candidate); break
            }
        }
        let (listener, port) = try XCTUnwrap(bound, "no free port for the test listener")

        let accepted = expectation(description: "listener accepted the connection")
        listener.newConnectionHandler = { conn in conn.start(queue: .global()); accepted.fulfill() }
        listener.start(queue: .global())
        defer { listener.cancel() }

        let iface = TCPClientInterface(name: "keepalive", host: "127.0.0.1", port: port)
        defer { iface.stop() }
        try iface.start()

        wait(for: [accepted], timeout: 10)
    }
}
