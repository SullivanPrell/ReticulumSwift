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
}
