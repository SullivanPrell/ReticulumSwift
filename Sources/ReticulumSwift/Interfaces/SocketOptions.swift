import Foundation
import Network

/// The **only** place in this package where socket options are constructed.
///
/// `bugs/023`. Python sets its socket options on every TCP socket it opens, in both directions:
/// the dialling branch at `TCPInterface.py:145-149` and the accepted-socket branch at `:241` and
/// `:259-261`, which is reached from `:591` where `TCPServerInterface` builds a client interface
/// out of the socket it just accepted. Direction does not decide whether the options apply.
///
/// The 1.7.0 release fixed the two dial paths and left `TCPServerInterface.start()` passing
/// `.tcp` — Network.framework's defaults, keepalive **off** — so a listening interface's accepted
/// connections could not notice a peer that vanished without sending FIN. It kept reporting Up
/// and discarding everything sent through it. The CHANGELOG claimed "every socket"; it was two of
/// four.
///
/// So the options live here and nowhere else, and `SocketOptionsTests` fails if any other file in
/// `Sources/` constructs an `NWProtocolTCP.Options`, an `NWParameters`, or opens a socket with a
/// stock `.tcp` parameter set. That structural check is the enforceable half: Network.framework
/// publishes no authoritative readback for TCP options — `NWParameters.defaultProtocolStack
/// .transportProtocol` is a *different* instance than the one handed to `NWParameters(tls:tcp:)`
/// and reports framework defaults on some OS versions — so "did this socket get keepalive?"
/// cannot be asked of a live connection. What the port controls is which object it hands over.
enum RNSSocketOptions {

    // MARK: - Python's constants (`TCPInterface.py:83-86`)

    /// `TCP_KEEPIDLE` — idle seconds before the first probe. Python `TCP_PROBE_AFTER`.
    static let probeAfter: Int = 5
    /// `TCP_KEEPINTVL` — seconds between probes. Python `TCP_PROBE_INTERVAL`.
    static let probeInterval: Int = 2
    /// `TCP_KEEPCNT` — unanswered probes before the connection is dead. Python `TCP_PROBES`.
    static let probes: Int = 12
    /// `TCP_USER_TIMEOUT` — give up on unacknowledged data after this many seconds. Python
    /// `TCP_USER_TIMEOUT`; Network.framework spells it `connectionDropTime`.
    static let userTimeout: Int = 24

    /// The looser set Python uses for a socket carrying I2P-tunneled traffic
    /// (`TCPInterface.py:92-95`), selected by the `i2p_tunneled` flag at `:182` and `:204`. I2P
    /// round-trips are long enough that the direct-TCP timers would tear down a healthy tunnel.
    static let i2pProbeAfter: Int = 10
    static let i2pProbeInterval: Int = 9
    static let i2pProbes: Int = 5
    static let i2pUserTimeout: Int = 45

    // MARK: - Network.framework

    /// The full option set every Reticulum TCP socket carries: `TCP_NODELAY`, keepalive with
    /// Python's three timers, and the user timeout (`TCPInterface.py:145-149` dialling,
    /// `:241`/`:259-261` accepting).
    ///
    /// A fresh instance per call — `NWProtocolTCP.Options` is a reference type and one already
    /// handed to a live connection or listener cannot be reused.
    static func tcpOptions() -> NWProtocolTCP.Options {
        let options = NWProtocolTCP.Options()
        // Python: `SO_KEEPALIVE, 1` + TCP_KEEPIDLE / TCP_KEEPINTVL / TCP_KEEPCNT.
        options.enableKeepalive = true
        options.keepaliveIdle = probeAfter
        options.keepaliveInterval = probeInterval
        options.keepaliveCount = probes
        options.connectionDropTime = userTimeout
        // RNS packets are small and latency-sensitive; Nagle would hold them behind the
        // delayed-ACK timer.
        options.noDelay = true
        return options
    }

    /// `TCP_NODELAY` only, with keepalive deliberately **off** — what Python's shared-instance
    /// interface sets, on its dial (`LocalInterface.py:147`) and on each socket its server
    /// accepts (`:100`). `LocalClientInterface` calls no `set_timeouts_*`; its only keepalive is
    /// the application-level `phy_keepalive` flag Python raises on Android, which is not a
    /// socket option.
    ///
    /// Kept distinct from ``tcpOptions()`` rather than folded into it: enabling keepalive here
    /// would exceed the reference on a loopback socket, and the point of this type is that the
    /// option set is chosen deliberately at one place, not inherited by accident.
    static func localOptions() -> NWProtocolTCP.Options {
        let options = NWProtocolTCP.Options()
        options.noDelay = true
        return options
    }

    /// The option set for a socket carrying I2P-tunneled traffic — keepalive on, but with
    /// Python's I2P timers rather than its direct-TCP ones (`TCPInterface.py:190-194`, `:204-207`,
    /// reached because `I2PInterface` and `I2PInterfacePeer` both set `i2p_tunneled = True`,
    /// `I2PInterface.py:742`, `:356`).
    static func i2pOptions() -> NWProtocolTCP.Options {
        let options = NWProtocolTCP.Options()
        options.enableKeepalive = true
        options.keepaliveIdle = i2pProbeAfter
        options.keepaliveInterval = i2pProbeInterval
        options.keepaliveCount = i2pProbes
        options.connectionDropTime = i2pUserTimeout
        options.noDelay = true
        return options
    }

    /// Parameters carrying ``tcpOptions()``, plus the options instance they were built from.
    ///
    /// Both are returned because the options object is the only one whose values can be read
    /// back — see the type comment. A caller keeps `options` so a test can assert on the exact
    /// instance the framework was handed.
    static func tcpParameters() -> (parameters: NWParameters, options: NWProtocolTCP.Options) {
        let options = tcpOptions()
        return (NWParameters(tls: nil, tcp: options), options)
    }

    /// Parameters carrying ``localOptions()``, plus the options instance they were built from.
    ///
    /// Also sets `allowLocalEndpointReuse`, the framework's `SO_REUSEADDR`. Every listener built
    /// from these binds a fixed loopback port that a previous run of the same daemon may just
    /// have released, and without reuse the bind fails with `EADDRINUSE` against a `TIME_WAIT`
    /// socket. Python sets it on the equivalent listeners — `multiprocessing.connection`'s
    /// `SocketListener.__init__` for the instance-control port, and `socketserver` for the
    /// shared instance — so a Python daemon rebinds where this one could not (`bugs/040`).
    ///
    /// Unlike the TCP options above, this one *is* readable back off the object the framework is
    /// handed, so `RPCServerBindTests` asserts it directly.
    static func localParameters() -> (parameters: NWParameters, options: NWProtocolTCP.Options) {
        let options = localOptions()
        let parameters = NWParameters(tls: nil, tcp: options)
        parameters.allowLocalEndpointReuse = true
        return (parameters, options)
    }

    /// ``localParameters()`` constrained to a loopback **bind** — for listeners, never dials.
    ///
    /// Python's control listener is constructed on the address `("127.0.0.1", port)`
    /// (`Reticulum.py:352` → `:359`), so it is unreachable off-host by construction. The Swift
    /// listener took ``localParameters()``, which carries no local endpoint — Network.framework
    /// then binds the wildcard, and the authenticated instance-control socket answered on every
    /// network the host was attached to.
    ///
    /// A separate function rather than a flag on ``localParameters()`` because that one is shared
    /// with `LocalInterface`'s outbound dial, where a required *local* endpoint would pin the
    /// source address of a connect. The port lives in the endpoint, so a listener built from
    /// these parameters uses `NWListener(using:)` — handing a port to the `on:` overload as well
    /// would be two sources of truth for one bind.
    static func localListenerParameters(port: NWEndpoint.Port)
        -> (parameters: NWParameters, options: NWProtocolTCP.Options) {
        let (parameters, options) = localParameters()
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)
        return (parameters, options)
    }

    /// Parameters carrying ``i2pOptions()``, plus the options instance they were built from.
    static func i2pParameters() -> (parameters: NWParameters, options: NWProtocolTCP.Options) {
        let options = i2pOptions()
        return (NWParameters(tls: nil, tcp: options), options)
    }

    // MARK: - POSIX

    /// Apply the shared-instance option set to a raw file descriptor.
    ///
    /// `PosixTCPServer` binds and accepts with POSIX sockets rather than Network.framework, so it
    /// cannot take an `NWParameters`. It is still a socket-opening site, and Python sets
    /// `TCP_NODELAY` on every socket its shared-instance server accepts
    /// (`LocalInterface.py:98-100`) — which this port did not, on either the listening socket or
    /// the accepted ones. Found while building the factory; not in `bugs/023` as filed.
    ///
    /// Unlike the Network.framework paths this one *is* verifiable: `getsockopt` reads the value
    /// straight back, so `SocketOptionsTests` asserts the accepted descriptor's real state.
    static func applyLocalOptions(toFileDescriptor fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, Int32(IPPROTO_TCP), TCP_NODELAY,
                   &one, socklen_t(MemoryLayout<Int32>.size))
    }
}
