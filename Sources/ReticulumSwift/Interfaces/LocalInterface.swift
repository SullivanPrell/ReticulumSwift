import Foundation
import Network

/// Connects to a locally running rnsd daemon via TCP (default port 37428).
///
/// Mirrors Python's `LocalClientInterface`. Uses HDLC framing identical to
/// `TCPClientInterface` and automatically reconnects after disconnection.
///
/// Usage:
/// ```swift
/// let local = LocalInterface()
/// transport.register(interface: local)
/// try local.start()
/// ```
public final class LocalInterface: Interface, MtuAutoconfiguringInterface {
    /// Per-interface mutable configuration (mode, announce rate control, ingress/egress
    /// control, the `ic_*` tunables). One stored property satisfies the whole settable set;
    /// see `InterfaceState` and `swift_devel/bugs/025-*.md`.
    public let interfaceState = InterfaceState()

    /// Mirrors Python's `Interface.announces_to_internal` (RNS 1.4.1).
    public var announcesToInternal: Bool? = nil
    /// Mirrors Python's `Interface.gravity` (RNS 1.4.1).
    public var gravity: Int = InterfaceMode.defaultGravity
    public let name: String
    public let host: String
    public let port: UInt16
    public var bitrate: Int = 1_000_000_000  // rnsd local = effectively unlimited

    /// `LocalClientInterface.HW_MTU = 262144` (`LocalInterface.py:71`). Without it this
    /// interface reported no hardware MTU at all, which disables link-MTU discovery for every
    /// link that crosses a Swift shared instance — stuck at the 500-byte default where the
    /// Python pair negotiates upward.
    public var hwMtu: Int? = 262_144

    /// `AUTOCONFIGURE_MTU = True` (`LocalInterface.py:64`). Python only *runs* the optimiser
    /// here from the `_force_shared_instance_bitrate` branch (`Reticulum.py:424-428`), so the
    /// 262144 stands in normal operation.
    public let autoconfigureMtu: Bool = true

    private let onlineFlag = LockedFlag(false)
    public private(set) var isOnline: Bool {
        get { onlineFlag.value }
        set { onlineFlag.value = newValue }
    }

    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = Constants.defaultIfacSize

    /// Lock-guarded — written from this interface's I/O queue while the UI
    /// and status reporting read from another thread. See `InterfaceCounters`.
    private let counters = InterfaceCounters()
    public var rxBytes: Int { counters.rxBytes }
    public var txBytes: Int { counters.txBytes }

    /// Seconds between reconnection attempts. Mirrors Python `LocalClientInterface.RECONNECT_WAIT = 8`.
    public var reconnectWait: TimeInterval = 8
    /// Maximum reconnect attempts. nil = unlimited (mirrors Python's `RECONNECT_MAX_TRIES = None`).
    public var maxReconnectTries: Int?
    /// Seconds `start()` will wait for the initial connection before giving up.
    /// Python's `connect()` is a blocking `socket.connect()` with no explicit
    /// deadline of its own; the cap here plays the role of the OS connect timeout
    /// so a wedged shared instance cannot hang a utility's startup forever.
    public var connectTimeout: TimeInterval = 5

    /// Raised by ``start()`` when the shared instance could not be reached.
    /// Python raises out of `LocalClientInterface.connect()`, which
    /// `Reticulum.__start_local_client` turns into "Local shared instance appears
    /// to be running, but it could not be connected".
    public enum ConnectionError: Error, CustomStringConvertible {
        case couldNotConnect(host: String, port: UInt16)

        public var description: String {
            if case .couldNotConnect(let host, let port) = self {
                return "could not connect to shared instance at \(host):\(port)"
            }
            return "could not connect to shared instance"
        }
    }

    private var connection: NWConnection?

    /// The exact `NWProtocolTCP.Options` instance the last dial handed to Network.framework,
    /// recorded because it is the only thing assertable — see ``RNSSocketOptions``.
    private(set) var handedOverTCPOptionsForTesting: NWProtocolTCP.Options?
    private let queue: DispatchQueue
    private let decoder = HDLC.FrameDecoder()
    private var reconnectTimer: DispatchSourceTimer?
    private var reconnectCount: Int = 0
    private var stopped = false
    /// Guards `stopped`, `connection`, and `reconnectTimer`, which are touched
    /// both from the caller thread (start/stop/send) and the interface's serial
    /// queue (connect/stateUpdate/scheduleReconnect/receive). Without it, a
    /// reconnect scheduled on the queue can assign `connection` just after
    /// stop() nil'd it, leaking a connection that keeps reconnecting.
    private let stateLock = NSLock()

    private var isStopped: Bool { stateLock.lock(); defer { stateLock.unlock() }; return stopped }

    /// Python `LocalClientInterface.__str__` returns `"LocalInterface[<port>]"`.
    /// This is used by rnstatus to filter out the client-side local interface.
    public var displayName: String { "LocalInterface[\(port)]" }

    /// This class is Python's `LocalClientInterface` — the client half of the shared
    /// instance. The Swift name says "LocalInterface", which is Python's `__str__`, not its
    /// class name, so the stats payload would otherwise publish the wrong kind.
    public var statsTypeName: String { "LocalClientInterface" }

    public init(
        name: String = "LocalInterface",
        host: String = "127.0.0.1",
        port: UInt16 = 37428
    ) {
        self.name = name
        self.host = host
        self.port = port
        self.queue = DispatchQueue(label: "ReticulumSwift.LocalInterface.\(name)")
    }

    /// Connect to the shared instance, returning only once the interface can
    /// actually send — or throwing if it cannot connect at all.
    ///
    /// Python's `LocalClientInterface.connect()` is a blocking `socket.connect()`
    /// that sets `online = True` on the line after it returns, so by the time
    /// `Reticulum.__start_local_client` hands back, the client can send. Swift's
    /// `NWConnection` is asynchronous, so returning as soon as it had been
    /// *started* left a window in which `send()` silently discarded everything —
    /// including the announce every utility fires immediately after attaching,
    /// which is how a Swift local client ended up invisible to the path table of
    /// the Swift shared instance it was attached to.
    public func start() throws {
        stateLock.lock()
        stopped = false
        reconnectCount = 0
        stateLock.unlock()

        let ready = DispatchSemaphore(value: 0)
        connect(signalling: ready)

        guard ready.wait(timeout: .now() + connectTimeout) == .success, isOnline else {
            // Python raises out of connect() and the interface is discarded, so
            // leave nothing running: a caller that got an error must not later
            // find itself silently online through a background reconnect.
            stop()
            throw ConnectionError.couldNotConnect(host: host, port: port)
        }
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
        counters.addTx(bytes: raw.count)
        conn.send(content: framed, completion: .contentProcessed { _ in })
    }

    /// - Parameter signalling: when non-nil, this is the *initial* connect made
    ///   on behalf of ``start()``. The semaphore is signalled once the outcome is
    ///   known, and a failure is reported back rather than retried, matching
    ///   Python — where a first connect that fails raises instead of entering the
    ///   reconnect loop. Reconnects pass nil and keep the existing retry behaviour.
    private func connect(signalling readySignal: DispatchSemaphore? = nil) {
        // Consumed by whichever state arrives first; cleared so that a later
        // failure on an already-established connection still schedules reconnects.
        // Only ever touched from `queue`, which is serial.
        var pendingReady = readySignal

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        // Re-check `stopped` and publish the new connection atomically so a
        // concurrent stop() either wins (we bail) or cancels the connection we
        // just assigned (the .cancelled handler then sees stopped and bails).
        stateLock.lock()
        guard !stopped else {
            stateLock.unlock()
            // Nothing will ever reach the state handler, so release start()
            // now rather than leaving it to time out.
            pendingReady?.signal(); pendingReady = nil
            return
        }
        // Python's `LocalClientInterface.connect()` sets `TCP_NODELAY` on its TCP socket
        // (`LocalInterface.py:147`), as does the branch that adopts an accepted one (`:98-100`).
        // It sets no keepalive — its only one is the application-level `phy_keepalive` flag on
        // Android — so this takes the shared-instance option set rather than the full TCP one.
        // Through 1.7.0 this line passed `.tcp`: framework defaults, Nagle on (`bugs/023`).
        let socketOptions = RNSSocketOptions.localParameters()
        handedOverTCPOptionsForTesting = socketOptions.options
        let conn = NWConnection(to: endpoint, using: socketOptions.parameters)
        // Cancel whatever we are replacing. A reconnect fires from a timer, not
        // from stop(), so the predecessor is still live here; leaving it dangling
        // leaks the socket and the shared instance keeps counting it as an
        // attached client.
        let superseded = connection
        connection = conn
        stateLock.unlock()
        superseded?.cancel()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            // Every arm below acts on "the interface's connection". After a
            // stop()/start() cycle this handler can still fire for a superseded
            // connection — its .cancelled arrives after the replacement is already
            // live — and acting on that would take the *healthy* connection
            // offline and schedule a reconnect that abandons it uncancelled: a
            // leaked socket the shared instance still counts as an attached
            // client, plus two concurrent receive loops on one HDLC decoder.
            // Python guards the same window with `if not self.reconnecting`.
            let isCurrent: Bool = {
                self.stateLock.lock(); defer { self.stateLock.unlock() }
                return self.connection === conn
            }()
            guard isCurrent else {
                // Still release start() if this was its connection, or it would
                // block for the full timeout waiting on a dead attempt.
                pendingReady?.signal(); pendingReady = nil
                return
            }
            switch state {
            case .ready:
                self.stateLock.lock(); self.reconnectCount = 0; self.stateLock.unlock()
                self.isOnline = true
                // Release start() only after `isOnline` is set, so send() works
                // for the caller the instant start() returns.
                pendingReady?.signal(); pendingReady = nil
                self.beginReceiveLoop()
            case .waiting:
                // A refused connection surfaces as .waiting, not .failed —
                // NWConnection keeps retrying a connect that has no listener.
                // For the initial connect that is precisely the "nothing is
                // running on 37428" case, which must fail fast: start() is called
                // sequentially for every configured interface, so blocking here
                // for the full connectTimeout stalls all of them (and freezes the
                // UI if the caller is on the main thread). Python's blocking
                // socket.connect() gets ECONNREFUSED back in milliseconds.
                //
                // Only the *initial* connect bails. A reconnect legitimately sits
                // in .waiting until the shared instance comes back.
                if let waiter = pendingReady {
                    pendingReady = nil
                    self.isOnline = false
                    conn.cancel()
                    waiter.signal()
                }
            case .failed, .cancelled:
                self.isOnline = false
                if let waiter = pendingReady {
                    pendingReady = nil
                    waiter.signal()
                    return
                }
                self.stateLock.lock()
                let stopped = self.stopped
                let count = self.reconnectCount
                self.stateLock.unlock()
                guard !stopped else { return }
                if let max = self.maxReconnectTries, count >= max { return }
                self.scheduleReconnect()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func scheduleReconnect() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + reconnectWait)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isStopped else { return }
            self.connect()
        }
        timer.resume()
        stateLock.lock()
        reconnectCount += 1
        reconnectTimer?.cancel()
        reconnectTimer = timer
        stateLock.unlock()
    }

    private func beginReceiveLoop() {
        stateLock.lock()
        let conn = connection
        stateLock.unlock()
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let frames = self.decoder.feed(data)
                for frame in frames {
                    self.counters.addRx(bytes: frame.count)
                    if let h = self.rawInboundHandler {
                        h(frame, self)
                    } else if let packet = try? Packet.unpack(frame) {
                        self.inboundHandler?(packet, self)
                    }
                }
            }
            if error != nil || isComplete {
                self.isOnline = false
                if !self.isStopped {
                    self.scheduleReconnect()
                }
                return
            }
            self.beginReceiveLoop()
        }
    }
}
