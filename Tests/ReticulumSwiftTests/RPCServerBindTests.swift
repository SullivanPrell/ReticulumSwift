import XCTest
import Network
@testable import ReticulumSwift

/// The instance-control listener must actually be listening, and must say so truthfully.
///
/// Found by `tri-test`'s state round-trip cells (`bugs/040`): a Swift daemon restarted on a
/// config directory whose control port had recently served clients logs "RPC server started on
/// port N" and then has no socket there at all. `rnstatus`, `rnpath`, `rnprobe`, `rnid -r` and
/// `rnx` all answer "Could not connect to instance control socket" against a daemon that is
/// otherwise running and passing traffic.
///
/// Two independent defects at one site, and the second is what made the first invisible:
///
/// 1. The parameters carry no local-endpoint reuse, so the bind fails with `EADDRINUSE` against
///    a `TIME_WAIT` socket from the previous run. Python's listener is a
///    `multiprocessing.connection.Listener`, which sets `SO_REUSEADDR` (CPython
///    `connection.py`, `SocketListener.__init__`), so a Python daemon rebinds where this one
///    cannot.
/// 2. `NWListener.start(queue:)` is asynchronous and reports failure through
///    `stateUpdateHandler`. None was set, so nothing observed the failure and the success line
///    was logged unconditionally. Python raises: `except OSError: self._socket.close(); raise`.
final class RPCServerBindTests: XCTestCase {

    private func freePort() -> UInt16 {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        var out = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &out) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) }
        }
        return UInt16(bigEndian: out.sin_port)
    }

    /// The parameters handed to `NWListener` allow local endpoint reuse.
    ///
    /// Asserted on the object the code constructs, not read back from the framework — the whole
    /// point of `bugs/013`'s `NWParameters` lesson is that
    /// `defaultProtocolStack.transportProtocol` is a *different* instance that reports defaults.
    /// `allowLocalEndpointReuse` is a plain property of the parameters object itself, so this is
    /// the value that is really passed.
    func testLocalParametersAllowEndpointReuse() {
        XCTAssertTrue(RNSSocketOptions.localParameters().parameters.allowLocalEndpointReuse,
                      """
                      the control listener must set local endpoint reuse, as Python's \
                      `multiprocessing.connection.Listener` sets `SO_REUSEADDR`. Without it a \
                      daemon restarted while the previous run's control connections are still in \
                      TIME_WAIT cannot bind, and every rn* utility loses the daemon while it \
                      keeps running.
                      """)
    }

    /// A listener that cannot bind is a failure, not a log line.
    ///
    /// Holding the port with a POSIX socket that does *not* set `SO_REUSEADDR` makes the bind
    /// fail deterministically even with reuse enabled on the listener side, so this stays a real
    /// assertion after the fix above rather than becoming unreachable.
    func testStartThrowsWhenThePortCannotBeBound() throws {
        let port = freePort()
        let blocker = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(blocker) }
        var one: Int32 = 1
        setsockopt(blocker, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = port.bigEndian
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(blocker, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try XCTSkipIf(bound != 0, "could not hold port \(port) to block the listener")
        listen(blocker, 1)

        let server = RPCServer(port: port, authkey: Data(repeating: 0x01, count: 32))
        XCTAssertThrowsError(try server.start(),
                             """
                             `NWListener.start(queue:)` returns before the bind is attempted and \
                             reports failure through `stateUpdateHandler`. With none set, a \
                             listener that never binds logged "RPC server started" and the daemon \
                             ran on with no control socket — a component reporting success it \
                             did not achieve, which is the shape this whole change is about. \
                             Python raises here (`SocketListener.__init__`).
                             """)
        server.stop()
    }

    /// And the ordinary case still works: a free port binds, and the socket is reachable when
    /// `start()` returns — so a caller may talk to it immediately rather than racing the bind.
    func testStartBindsAndIsReachableOnReturn() throws {
        let port = freePort()
        let server = RPCServer(port: port, authkey: Data(repeating: 0x02, count: 32))
        try server.start()
        defer { server.stop() }

        let probe = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(probe) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = port.bigEndian
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(probe, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connected, 0,
                       "the control socket must accept connections once `start()` has returned; "
                       + "otherwise every utility racing daemon startup sees "
                       + "\"Could not connect to instance control socket\"")
    }

    /// The first non-loopback, non-link-local IPv4 address this host holds, or nil.
    private func nonLoopbackIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let sa = entry.pointee.ifa_addr,
                  sa.pointee.sa_family == sa_family_t(AF_INET),
                  (entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var addr = sockaddr_in()
            memcpy(&addr, sa, MemoryLayout<sockaddr_in>.size)
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil
            else { continue }
            let text = String(cString: buffer)
            if text.hasPrefix("169.254.") { continue }
            return text
        }
        return nil
    }

    /// The bind must be loopback-**only**, which reachability alone cannot prove.
    ///
    /// Python's control listener is constructed on `("127.0.0.1", port)` (`Reticulum.py:352` →
    /// `:359`), so it is unreachable off-host by construction. This is the negative assertion
    /// whose absence let a wildcard bind sit behind 3258 green tests: the test above proves
    /// 127.0.0.1 answers, and a listener on `*` passes that too. An authenticated management
    /// socket (path drops, blackholing) must not be reachable from every network the host is on.
    func testTheControlSocketIsNotReachableOnANonLoopbackAddress() throws {
        guard let lanAddress = nonLoopbackIPv4() else {
            throw XCTSkip("host has no non-loopback IPv4 address to probe")
        }
        let port = freePort()
        let server = RPCServer(port: port, authkey: Data(repeating: 0x03, count: 32))
        try server.start()
        defer { server.stop() }

        let probe = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(probe) }
        // Bound: connecting to the host's own address answers immediately (accept or RST),
        // but never let a pathological stack hang the suite.
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(probe, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr(lanAddress)
        addr.sin_port = port.bigEndian
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(probe, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertNotEqual(connected, 0,
                          """
                          the control socket accepted a connection on \(lanAddress):\(port) — \
                          the listener is bound to the wildcard, so the instance-control RPC \
                          port is reachable from every network this host is on, where Python's \
                          identical listener binds ("127.0.0.1", port) and is unreachable \
                          off-host by construction (Reticulum.py:352, :359)
                          """)
    }
}
