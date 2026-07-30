import XCTest
import Network
@testable import ReticulumSwift

/// `bugs/023` — every socket this port opens must carry the reference socket options, in both
/// directions.
///
/// The gate here is unusual, and deliberately so (design D4 / risk R5). There is no authoritative
/// way to ask a live connection whether keepalive is on: Network.framework publishes no getters
/// for TCP options, and `NWParameters.defaultProtocolStack.transportProtocol` hands back a
/// *different* `NWProtocolTCP.Options` instance than the one given to `NWParameters(tls:tcp:)`,
/// reporting framework defaults on some OS versions. That is what CI's one deliberately-skipped
/// test from 1.7.0 records. And proving keepalive *fires* needs a peer that stops answering
/// without the kernel sending FIN — packet-level filtering, not `close()`.
///
/// So the enforceable invariant is **construction-site uniqueness**: one factory builds the
/// options, and every socket-opening site takes them from it. That is a weaker claim than
/// "keepalive works", and it is stated as such rather than dressed up. Where a real readback
/// exists — the POSIX shared-instance server — this suite uses it.
final class SocketOptionsTests: XCTestCase {

    // MARK: - The factory's values

    func testFactoryCarriesThePythonTCPOptionValues() {
        let options = RNSSocketOptions.tcpOptions()
        // TCPInterface.py:83-86 and set_timeouts_osx / set_timeouts_linux at :181-206.
        XCTAssertTrue(options.enableKeepalive, "Python sets SO_KEEPALIVE on every TCP socket")
        XCTAssertEqual(options.keepaliveIdle, 5,      "TCP_PROBE_AFTER")
        XCTAssertEqual(options.keepaliveInterval, 2,  "TCP_PROBE_INTERVAL")
        XCTAssertEqual(options.keepaliveCount, 12,    "TCP_PROBES")
        XCTAssertEqual(options.connectionDropTime, 24, "TCP_USER_TIMEOUT")
        XCTAssertTrue(options.noDelay, "TCPInterface.py:149, :241 — TCP_NODELAY on every socket")
    }

    /// The shared-instance option set is `TCP_NODELAY` only. Python's `LocalClientInterface`
    /// calls no `set_timeouts_*` on either its dial (`LocalInterface.py:147`) or the sockets its
    /// server accepts (`:100`), so enabling keepalive there would exceed the reference.
    func testFactoryLeavesKeepaliveOffForTheSharedInstanceOptionSet() {
        let options = RNSSocketOptions.localOptions()
        XCTAssertTrue(options.noDelay, "LocalInterface.py:100, :147 — TCP_NODELAY")
        XCTAssertFalse(options.enableKeepalive,
                       "Python's LocalClientInterface sets no keepalive; its only one is the "
                       + "application-level phy_keepalive flag on Android, not a socket option")
    }

    /// A fresh instance per call, because one already handed to a live connection cannot be
    /// reused — and because a shared mutable options object would let one interface's
    /// configuration leak into another's socket.
    func testFactoryReturnsAFreshInstancePerCall() {
        XCTAssertFalse(RNSSocketOptions.tcpOptions() === RNSSocketOptions.tcpOptions())
        XCTAssertFalse(RNSSocketOptions.tcpParameters().parameters
                       === RNSSocketOptions.tcpParameters().parameters)
    }

    // MARK: - The handed-over object, per site

    func testTCPServerListenerIsBuiltFromTheFactoryOptions() throws {
        let server = TCPServerInterface(name: "optserver", port: 45_931)
        try server.start()
        defer { server.stop() }

        let handed = try XCTUnwrap(server.handedOverTCPOptionsForTesting,
                                  """
                                  TCPServerInterface.start() recorded no options object, which \
                                  means it did not take one from the factory. Before bugs/023 it \
                                  called NWListener(using: .tcp) — framework defaults, keepalive \
                                  off — so every connection it accepted was unable to notice a \
                                  peer that vanished without sending FIN.
                                  """)
        XCTAssertTrue(handed.enableKeepalive)
        XCTAssertTrue(handed.noDelay)
        XCTAssertEqual(handed.keepaliveIdle, RNSSocketOptions.probeAfter)
        XCTAssertEqual(handed.keepaliveInterval, RNSSocketOptions.probeInterval)
        XCTAssertEqual(handed.keepaliveCount, RNSSocketOptions.probes)
        XCTAssertEqual(handed.connectionDropTime, RNSSocketOptions.userTimeout)
    }

    func testTCPClientDialIsBuiltFromTheFactoryOptions() throws {
        // Dials a closed port: `connect()` runs and records its options regardless of whether
        // the connection ever reaches .ready, which is what this asserts.
        let client = TCPClientInterface(name: "optclient", host: "127.0.0.1", port: 45_932)
        try client.start()
        defer { client.stop() }

        let handed = try XCTUnwrap(client.handedOverTCPOptionsForTesting)
        XCTAssertTrue(handed.enableKeepalive)
        XCTAssertTrue(handed.noDelay)
    }

    func testLocalInterfaceDialIsBuiltFromTheSharedInstanceOptionSet() throws {
        let local = LocalInterface(name: "optlocal", port: 45_933)
        // Nothing is listening, so start() will not come up; the dial still happens.
        try? local.start()
        defer { local.stop() }

        let handed = try XCTUnwrap(local.handedOverTCPOptionsForTesting,
                                   "LocalInterface.connect() used NWConnection(to:using: .tcp) "
                                   + "before bugs/023 — the framework's defaults, which do not "
                                   + "include the TCP_NODELAY Python sets at LocalInterface.py:147")
        XCTAssertTrue(handed.noDelay)
        XCTAssertFalse(handed.enableKeepalive, "matches LocalInterface.py, which sets no keepalive")
    }

    /// An accepted connection is not constructed by this port at all — Network.framework derives
    /// it from the listener's parameters — so routing the listener through the factory is what
    /// covers every accepted connection. Asserted rather than assumed.
    func testAcceptedConnectionInheritsTheListenerParameters() throws {
        let server = TCPServerInterface(name: "optaccept", port: 45_934)
        try server.start()
        defer { server.stop() }

        let accepted = expectation(description: "accepted")
        server.acceptedConnectionParametersForTesting = { _ in accepted.fulfill() }

        let client = NWConnection(to: .hostPort(host: "127.0.0.1", port: 45_934),
                                  using: RNSSocketOptions.tcpParameters().parameters)
        client.start(queue: .global())
        defer { client.cancel() }
        wait(for: [accepted], timeout: 5.0)

        let listenerParams = try XCTUnwrap(server.handedOverParametersForTesting)
        let acceptedParams = try XCTUnwrap(server.lastAcceptedParametersForTesting)
        XCTAssertTrue(acceptedParams === listenerParams,
                      """
                      The accepted connection's parameters are not the listener's object. If \
                      Network.framework ever stops passing them through, fixing the listener \
                      would no longer cover accepted sockets and this port would need to \
                      configure each one — which is what bugs/023 is about.
                      """)
    }

    /// The one site with a real readback. `PosixTCPServer` binds with POSIX sockets, and Python
    /// sets `TCP_NODELAY` on every socket its shared-instance server accepts
    /// (`LocalInterface.py:98-100`), so `getsockopt` can be asked directly.
    func testAcceptedSharedInstanceSocketHasNoDelaySet() throws {
        let server = PosixTCPServer(name: "Shared Instance", port: 45_935)
        try server.start()
        defer { server.stop() }

        let accepted = expectation(description: "accepted")
        server.acceptedDescriptorHandlerForTesting = { _ in accepted.fulfill() }

        let client = NWConnection(to: .hostPort(host: "127.0.0.1", port: 45_935),
                                  using: RNSSocketOptions.localParameters().parameters)
        client.start(queue: .global())
        defer { client.cancel() }
        wait(for: [accepted], timeout: 5.0)

        let fd = try XCTUnwrap(server.lastAcceptedDescriptorForTesting)
        var value: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        let rc = getsockopt(fd, Int32(IPPROTO_TCP), TCP_NODELAY, &value, &length)
        XCTAssertEqual(rc, 0, "getsockopt failed on the accepted descriptor")
        XCTAssertNotEqual(value, 0,
                          """
                          TCP_NODELAY is off on the socket the shared-instance server accepted. \
                          Python sets it at LocalInterface.py:100, on the accepted socket, in the \
                          same branch the dial path sets it. This port set only SO_NOSIGPIPE — \
                          the accept-path half of bugs/023, in the POSIX server rather than the \
                          Network.framework one.
                          """)
    }

    // MARK: - Construction-site uniqueness

    /// The structural guard, and the actual enforcement (D4).
    ///
    /// A behavioural test cannot see this defect — that is why 1.7.0 shipped claiming "every
    /// socket" while two of the four sites still took framework defaults. A test that fails on
    /// any socket opened with stock parameters, anywhere in `Sources/`, can.
    func testNoSocketIsOpenedOutsideTheSharedFactory() throws {
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ReticulumSwiftTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("Sources")

        /// The file that is *allowed* to construct options — the factory itself.
        let sanctioned = "SocketOptions.swift"

        /// Patterns that mean "a socket configured by something other than the factory".
        /// `.udp` is not listed: Python opens its UDP sockets with no TCP options at all
        /// (`UDPInterface.py`), so a stock UDP parameter set is correct.
        let banned: [(pattern: String, why: String)] = [
            ("NWProtocolTCP.Options(",
             "constructs TCP options outside the factory — use RNSSocketOptions"),
            ("using: .tcp",
             "opens a TCP socket with Network.framework's defaults, which have keepalive off "
             + "and Nagle on (TCPInterface.py:145-149, :241, :259-261)"),
            ("NWParameters(tls:",
             "assembles its own parameters — use RNSSocketOptions.tcpParameters() / "
             + "localParameters()"),
        ]

        var offences: [String] = []
        let files = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift", url.lastPathComponent != sanctioned else { continue }
            let src = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in src.components(separatedBy: .newlines).enumerated() {
                // Comments cite these strings freely; only code counts.
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///"), !code.hasPrefix("*") else {
                    continue
                }
                for entry in banned where code.contains(entry.pattern) {
                    offences.append("  \(url.lastPathComponent):\(index + 1) — \(entry.why)\n"
                                    + "      \(code)")
                }
            }
        }

        XCTAssertTrue(offences.isEmpty,
                      """
                      \(offences.count) socket-opening site(s) bypass RNSSocketOptions:
                      \(offences.joined(separator: "\n"))
                      There must be exactly one place these options are constructed. Fixing the
                      sites a failing test happens to touch is what left bugs/023 half-done
                      through 1.7.0.
                      """)
    }
}
