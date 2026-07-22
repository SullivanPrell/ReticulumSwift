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
public final class LocalInterface: Interface {
    public let name: String
    public let host: String
    public let port: UInt16
    public private(set) var bitrate: Int = 1_000_000_000  // rnsd local = effectively unlimited
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

    private var connection: NWConnection?
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
        counters.addTx(bytes: raw.count)
        conn.send(content: framed, completion: .contentProcessed { _ in })
    }

    private func connect() {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        // Re-check `stopped` and publish the new connection atomically so a
        // concurrent stop() either wins (we bail) or cancels the connection we
        // just assigned (the .cancelled handler then sees stopped and bails).
        stateLock.lock()
        guard !stopped else { stateLock.unlock(); return }
        let conn = NWConnection(to: endpoint, using: .tcp)
        connection = conn
        stateLock.unlock()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.stateLock.lock(); self.reconnectCount = 0; self.stateLock.unlock()
                self.isOnline = true
                self.beginReceiveLoop()
            case .failed, .cancelled:
                self.isOnline = false
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
