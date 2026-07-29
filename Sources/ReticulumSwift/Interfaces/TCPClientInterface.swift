import Foundation
import Network

/// Connects to a remote Reticulum node over TCP and exchanges HDLC-framed
/// packet bytes. Wire-compatible with `RNS.Interfaces.TCPInterface` running
/// in HDLC mode (`kiss_framing=False`, the default).
public final class TCPClientInterface: Interface {
    public let name: String
    public let host: String
    public let port: UInt16
    public private(set) var bitrate: Int = 10_000_000
    private let onlineFlag = LockedFlag(false)
    public private(set) var isOnline: Bool {
        get { onlineFlag.value }
        set { onlineFlag.value = newValue }
    }

    // Python TCPClientInterface: HW_MTU = 262144, AUTOCONFIGURE_MTU = True
    public let hwMtu: Int? = 262_144
    public let autoconfigureMtu: Bool = true

    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = Constants.defaultIfacSize
    public var bootstrapOnly: Bool = false
    public var recursivePrs: Bool = false
    public var announcesFromInternal: Bool = true
    /// Mirrors Python's `Interface.announces_to_internal` (RNS 1.4.1).
    public var announcesToInternal: Bool? = nil
    /// Mirrors Python's `Interface.gravity` (RNS 1.4.1).
    public var gravity: Int = InterfaceMode.defaultGravity

    /// Seconds between reconnection attempts. Python: `TCPClientInterface.RECONNECT_WAIT = 5`.
    public var reconnectWait: TimeInterval = 5
    /// Maximum reconnect attempts. nil = unlimited, matching Python's
    /// `RECONNECT_MAX_TRIES = None`. Config key: `max_reconnect_tries`.
    public var maxReconnectTries: Int?

    /// Lock-guarded — written from this interface's I/O queue while the UI
    /// and status reporting read from another thread. See `InterfaceCounters`.
    private let counters = InterfaceCounters()
    public var rxBytes: Int { counters.rxBytes }
    public var txBytes: Int { counters.txBytes }

    private var connection: NWConnection?
    private let queue: DispatchQueue
    private let decoder = HDLC.FrameDecoder()
    private var reconnectTimer: DispatchSourceTimer?
    private var reconnectCount: Int = 0
    private var everConnected = false
    private var stopped = false
    private var dials = 0
    /// Guards `connection`, `reconnectTimer`, `reconnectCount`, `stopped` and
    /// `everConnected`, which are touched both from the caller thread (start/stop/send)
    /// and from this interface's serial queue (connect/stateUpdate/receive). Mirrors the
    /// same lock in ``LocalInterface``; without it a reconnect firing from the timer can
    /// assign `connection` just after `stop()` nil'd it, leaving a connection that keeps
    /// redialing after teardown.
    private let stateLock = NSLock()

    private var isStopped: Bool { stateLock.lock(); defer { stateLock.unlock() }; return stopped }

    /// Python `TCPClientInterface.__str__` (`TCPInterface.py:456-462`):
    /// `"TCPInterface["+str(self.name)+"/"+ip_str+":"+str(self.target_port)+"]"`, where
    /// `target_ip` is the configured `target_host` verbatim — Python never resolves it for
    /// display — and an IPv6 literal is bracketed.
    ///
    /// The `"Client on …"` form this used to emit belongs to a *server-spawned* client,
    /// whose `name` Python sets to `"Client on "+servername` (`TCPInterface.py:590`).
    /// `rnstatus` hides every interface whose name starts with `TCPInterface[Client`
    /// (`rnstatus.py:397`), so emitting the spawned form here made every interface an
    /// operator configured invisible in `rnstatus` — see `bugs/013`.
    public var displayName: String {
        let ipString = host.contains(":") ? "[\(host)]" : host
        return "TCPInterface[\(name)/\(ipString):\(port)]"
    }

    /// The live connection, for tests that need to assert on its state.
    var currentConnectionForTesting: NWConnection? {
        stateLock.lock(); defer { stateLock.unlock() }; return connection
    }
    /// How many times a connection has been dialed, initial attempt included.
    var dialCountForTesting: Int {
        stateLock.lock(); defer { stateLock.unlock() }; return dials
    }

    public init(name: String, host: String, port: UInt16) {
        self.name = name
        self.host = host
        self.port = port
        self.queue = DispatchQueue(label: "ReticulumSwift.TCPClientInterface.\(name)")
    }

    /// Python's `__init__` runs `initial_connect()` inline (`SYNCHRONOUS_START = True`) and,
    /// if that fails, starts the `reconnect()` thread rather than raising — a configured
    /// interface whose peer is down comes up unconnected and keeps trying. This returns as
    /// soon as the dial is in flight, which reaches the same state without stalling
    /// interface synthesis for `INITIAL_CONNECT_TIMEOUT` per unreachable peer.
    public func start() throws {
        stateLock.lock()
        stopped = false
        reconnectCount = 0
        stateLock.unlock()
        connect()
    }

    public func stop() {
        stateLock.lock()
        stopped = true
        let timer = reconnectTimer; reconnectTimer = nil
        let conn = connection; connection = nil
        stateLock.unlock()
        timer?.cancel()
        conn?.cancel()
        isOnline = false
    }

    public func send(_ packet: Packet) throws {
        stateLock.lock()
        let conn = connection
        stateLock.unlock()
        guard let conn, isOnline else { return }
        let raw = try packet.pack()
        let framed = HDLC.frame(wrapIfac(raw))
        counters.addTx(bytes: raw.count)   // Python counts raw (unframed) bytes
        conn.send(content: framed, completion: .contentProcessed { _ in })
    }

    // MARK: - Socket options

    /// Python's TCP socket options (`TCPInterface.py:83-86`), applied to every dial.
    ///
    /// `NWConnection(to:using: .tcp)` takes Network.framework's defaults, which have
    /// keepalive **off**. Without it a connection whose peer vanished without sending FIN
    /// — a machine that slept, a NAT that dropped the mapping, a peer that was hard-killed
    /// — stays `.ready` indefinitely: no event fires, the interface keeps reporting "Up",
    /// and everything sent through it is silently discarded. Keepalive is what turns that
    /// half-open connection into a failure the reconnect logic can act on.
    ///
    /// A fresh instance per call: `NWParameters` is a reference type and one already handed
    /// to a live connection cannot be reused.
    static var tcpParameters: NWParameters {
        let options = NWProtocolTCP.Options()
        // Python: `SO_KEEPALIVE, 1` + `TCP_KEEPIDLE = TCP_PROBE_AFTER`.
        options.enableKeepalive = true
        options.keepaliveIdle = 5           // TCP_PROBE_AFTER
        options.keepaliveInterval = 2       // TCP_PROBE_INTERVAL
        options.keepaliveCount = 12         // TCP_PROBES
        // Python's Linux path sets `TCP_USER_TIMEOUT`; Network.framework spells the same
        // "give up on an unacknowledged connection after N seconds" as connectionDropTime.
        options.connectionDropTime = 24     // TCP_USER_TIMEOUT
        // Python sets TCP_NODELAY on every socket it opens. RNS packets are small and
        // latency-sensitive; Nagle would hold them behind the delayed-ACK timer.
        options.noDelay = true
        return NWParameters(tls: nil, tcp: options)
    }

    // MARK: - Connect / reconnect

    private func connect() {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        // Re-check `stopped` and publish the new connection atomically, so a concurrent
        // stop() either wins (we bail) or cancels the connection we just assigned.
        stateLock.lock()
        guard !stopped else { stateLock.unlock(); return }
        let conn = NWConnection(to: endpoint, using: Self.tcpParameters)
        // Cancel whatever we are replacing. A reconnect fires from a timer, not from
        // stop(), so the predecessor is still live here — and a peer that sent FIN leaves
        // it in CLOSE_WAIT until something closes our half.
        let superseded = connection
        connection = conn
        dials += 1
        stateLock.unlock()
        superseded?.cancel()
        // Each connection gets a fresh frame decoder; carrying a half-decoded frame
        // across a reconnect would corrupt the first packet of the new session.
        decoder.reset()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            // After a redial this handler still fires for the superseded connection —
            // its `.cancelled` arrives once the replacement is already live. Acting on it
            // would take the healthy connection offline and schedule a redial that
            // abandons it uncancelled. Python guards the same window with
            // `if not self.reconnecting`.
            let isCurrent: Bool = {
                self.stateLock.lock(); defer { self.stateLock.unlock() }
                return self.connection === conn
            }()
            guard isCurrent else { return }

            switch state {
            case .ready:
                self.stateLock.lock()
                self.reconnectCount = 0
                let reconnected = self.everConnected
                self.everConnected = true
                self.stateLock.unlock()
                self.isOnline = true
                if reconnected {
                    // Python: `RNS.log("Reconnected socket for "+str(self)+".", LOG_INFO)`
                    Reticulum.log("Reconnected socket for \(self.displayName).", level: .info)
                } else {
                    Reticulum.log("Interface \(self.name) is up", level: .verbose)
                }
                self.beginReceiveLoop()

            case .waiting(let err):
                // A refused or unreachable peer surfaces as .waiting, not .failed, and
                // NWConnection keeps retrying underneath on its own schedule. Take it
                // over: cancel and redial on Python's clock, so the retry is visible in
                // the log and honours `max_reconnect_tries`.
                Reticulum.log("Connection attempt for \(self.displayName) failed: \(err)",
                              level: .debug)
                self.isOnline = false
                self.dropAndScheduleReconnect(conn)

            case .failed(let err):
                Reticulum.log("Connection for \(self.displayName) failed: \(err)", level: .debug)
                self.isOnline = false
                self.dropAndScheduleReconnect(conn)

            case .cancelled:
                self.isOnline = false

            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    /// Close the dead connection and arm the retry timer.
    ///
    /// Cancelling matters as much as retrying: without it the socket sits in `CLOSE_WAIT`
    /// for the life of the process once the peer has sent FIN.
    private func dropAndScheduleReconnect(_ conn: NWConnection) {
        conn.cancel()
        stateLock.lock()
        let stopped = self.stopped
        let count = reconnectCount
        stateLock.unlock()
        guard !stopped else { return }
        if let max = maxReconnectTries, count >= max {
            // Python: "Max reconnection attempts reached for …" then teardown.
            Reticulum.log("Max reconnection attempts reached for \(displayName)", level: .error)
            return
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + reconnectWait)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isStopped else { return }
            self.connect()
        }
        // Publish before resuming, and under the same lock that `stop()` takes. Resuming
        // first leaves a window in which a concurrent `stop()` cancels the *previous*
        // timer and never sees this one — an interface that keeps dialing after teardown.
        stateLock.lock()
        guard !stopped else { stateLock.unlock(); timer.cancel(); return }
        reconnectCount += 1
        reconnectTimer?.cancel()
        reconnectTimer = timer
        stateLock.unlock()
        timer.resume()
    }

    private func beginReceiveLoop() {
        stateLock.lock()
        let current = connection
        stateLock.unlock()
        guard let current else { return }
        current.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let frames = self.decoder.feed(data, hwMtu: self.hwMtu, ifacSize: self.ifacSize)
                for frame in frames {
                    self.counters.addRx(bytes: frame.count)   // Python counts unframed payload bytes
                    if let h = self.rawInboundHandler {
                        h(frame, self)
                    } else if let packet = try? Packet.unpack(frame) {
                        self.inboundHandler?(packet, self)
                    }
                }
            }
            if error != nil || isComplete {
                // A receive that completes on a superseded connection must not touch the
                // live one: it would take a healthy interface offline and start a second
                // retry loop.
                self.stateLock.lock()
                let isCurrent = self.connection === current
                self.stateLock.unlock()
                guard isCurrent else { return }
                // The peer hung up (or the link broke). Python drops out of `read_loop`
                // into `teardown()` → `reconnect()`; this used to just return, leaving the
                // node permanently and silently offline. See `bugs/013`.
                Reticulum.log("Interface \(self.name) lost its connection to \(self.host):\(self.port)",
                              level: .verbose)
                self.isOnline = false
                self.dropAndScheduleReconnect(current)
                return
            }
            self.beginReceiveLoop()
        }
    }
}
