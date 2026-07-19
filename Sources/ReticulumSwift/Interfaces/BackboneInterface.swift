import Foundation
import Network

/// High-bandwidth TCP backbone interface with HDLC framing and auto-reconnect.
///
/// Wire-compatible with Python's `RNS.Interfaces.BackboneInterface.BackboneClientInterface`.
/// Key differences from `TCPClientInterface`:
///   - `HW_MTU = 1_048_576` (1 MB vs 262 KB for TCP)
///   - `BITRATE_GUESS = 100_000_000` (100 Mbps)
///   - Automatic reconnection after disconnect
public final class BackboneInterface: Interface {

    // MARK: - Constants (mirrors Python BackboneClientInterface)

    /// Maximum hardware MTU in bytes.
    /// Python: `BackboneClientInterface.HW_MTU = BackboneInterface.HW_MTU = 1_048_576`.
    public static let hwMtuConstant: Int = 1_048_576

    /// Default bitrate estimate in bits per second.
    /// Python: `BackboneClientInterface.BITRATE_GUESS = 100_000_000`.
    public static let bitrateGuess: Int = 100_000_000

    /// Time in seconds to wait between reconnect attempts.
    /// Python: `BackboneClientInterface.RECONNECT_WAIT = 5`.
    public static let defaultReconnectWait: TimeInterval = 5.0

    /// Maximum number of reconnect attempts (nil = infinite).
    /// Python: `BackboneClientInterface.RECONNECT_MAX_TRIES = None`.
    public static let defaultMaxReconnectTries: Int? = nil

    // MARK: - Interface protocol properties

    public let name: String
    public let host: String
    public let port: UInt16
    public private(set) var bitrate: Int = BackboneInterface.bitrateGuess
    public private(set) var isOnline: Bool = false

    /// Python: `HW_MTU = 1_048_576`.
    public let hwMtu: Int? = BackboneInterface.hwMtuConstant

    /// Python: `AUTOCONFIGURE_MTU = True`.
    public let autoconfigureMtu: Bool = true

    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?
    public var recursivePrs: Bool = false
    public var announcesFromInternal: Bool = true

    // MARK: - IFAC (Interface Access Code)
    //
    // Real stored properties — the `Interface` protocol's default
    // implementations are no-op storage, so without these `configureIfac`
    // would silently discard the key and every outbound frame would go out
    // un-masked (dropped by IFAC-protected Python peers).
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = Constants.defaultIfacSize

    public private(set) var rxBytes: Int = 0
    public private(set) var txBytes: Int = 0

    // MARK: - Reconnect configuration

    /// Seconds to wait between reconnect attempts. Python: `RECONNECT_WAIT = 5`.
    public let reconnectWait: TimeInterval

    /// Maximum reconnect attempts (nil = infinite). Python: `RECONNECT_MAX_TRIES = None`.
    public let maxReconnectTries: Int?

    // MARK: - Private state

    private var connection: NWConnection?
    private let queue: DispatchQueue
    private let decoder = HDLC.FrameDecoder()
    private var reconnectAttempts: Int = 0
    /// True between scheduling a reconnect and it firing, so overlapping failure
    /// signals collapse to a single reconnect loop. Guarded by `stateLock`.
    private var reconnectPending: Bool = false

    /// Guards `_isStopped`, `connection`, `reconnectAttempts`, and `reconnectPending`, which are
    /// touched from the caller thread (start/stop/send) and the interface's
    /// serial queue (openConnection/stateUpdate/scheduleReconnect/receive). See
    /// the LocalInterface note: without it a queued reconnect can assign
    /// `connection` right after stop() cleared it, leaking a live socket.
    private let stateLock = NSLock()
    private var _isStopped: Bool = false
    private var isStopped: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isStopped }
        set { stateLock.lock(); _isStopped = newValue; stateLock.unlock() }
    }

    // MARK: - Init

    public init(
        name: String,
        host: String,
        port: UInt16,
        reconnectWait: TimeInterval = BackboneInterface.defaultReconnectWait,
        maxReconnectTries: Int? = BackboneInterface.defaultMaxReconnectTries
    ) {
        self.name = name
        self.host = host
        self.port = port
        self.reconnectWait = reconnectWait
        self.maxReconnectTries = maxReconnectTries
        self.queue = DispatchQueue(label: "ReticulumSwift.BackboneInterface.\(name)")
    }

    // MARK: - Interface lifecycle

    public func start() throws {
        stateLock.lock()
        _isStopped = false
        reconnectAttempts = 0
        stateLock.unlock()
        openConnection()
    }

    public func stop() {
        stateLock.lock()
        _isStopped = true
        let conn = connection; connection = nil
        stateLock.unlock()
        isOnline = false
        conn?.cancel()
    }

    // MARK: - Packet send

    public func send(_ packet: Packet) throws {
        stateLock.lock()
        let conn = connection
        stateLock.unlock()
        guard let conn, isOnline else { return }
        let raw = try packet.pack()
        let framed = framePacketBytes(raw)
        txBytes += raw.count
        conn.send(content: framed, completion: .contentProcessed { _ in })
    }

    /// Produce the on-wire bytes for an outbound packet: apply the IFAC mask
    /// (when configured) then HDLC-frame. Mirrors the central IFAC application
    /// in Python `Transport.transmit`, matching how `TCPClientInterface.send`
    /// frames its bytes. Factored out of `send(_:)` so the IFAC/framing path is
    /// unit-testable without a live `NWConnection`.
    func framePacketBytes(_ raw: Data) -> Data {
        HDLC.frame(wrapIfac(raw))
    }

    // MARK: - Connection management

    private func openConnection() {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let conn = NWConnection(to: endpoint, using: .tcp)
        // Re-check stopped and publish the connection atomically (see LocalInterface).
        stateLock.lock()
        guard !_isStopped else { stateLock.unlock(); return }
        connection = conn
        stateLock.unlock()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self, !self.isStopped else { return }
            switch state {
            case .ready:
                self.isOnline = true
                self.stateLock.lock(); self.reconnectAttempts = 0; self.stateLock.unlock()
                self.beginReceiveLoop()
                Reticulum.log("BackboneInterface \(self.name) connected to \(self.host):\(self.port)",
                              level: .debug)

            case .failed(let error):
                Reticulum.log("BackboneInterface \(self.name) connection failed: \(error)",
                              level: .warning)
                self.isOnline = false
                self.scheduleReconnect()

            case .cancelled:
                self.isOnline = false

            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    private func scheduleReconnect() {
        stateLock.lock()
        // A single disconnect can trigger both the .failed state handler and the
        // receive-error callback; `reconnectPending` collapses them so only ONE
        // reconnect loop is scheduled (was: two concurrent overlapping loops).
        if _isStopped || reconnectPending { stateLock.unlock(); return }
        let attempts = reconnectAttempts
        if let maxTries = maxReconnectTries, attempts >= maxTries {
            stateLock.unlock()
            Reticulum.log("BackboneInterface \(name) reached max reconnect tries (\(maxTries)), giving up.",
                          level: .error)
            return
        }
        reconnectAttempts = attempts + 1
        reconnectPending = true
        let attempt = reconnectAttempts
        stateLock.unlock()
        Reticulum.log("BackboneInterface \(name) scheduling reconnect in \(reconnectWait)s (attempt \(attempt))",
                      level: .verbose)

        queue.asyncAfter(deadline: .now() + reconnectWait) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            self.reconnectPending = false
            let stopped = self._isStopped
            self.stateLock.unlock()
            guard !stopped else { return }
            self.openConnection()
        }
    }

    private func beginReceiveLoop() {
        stateLock.lock()
        let conn = connection
        stateLock.unlock()
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, !self.isStopped else { return }

            if let data, !data.isEmpty {
                let frames = self.decoder.feed(data, hwMtu: self.hwMtu, ifacSize: self.ifacSize)
                for frame in frames {
                    self.rxBytes += frame.count
                    if let h = self.rawInboundHandler {
                        h(frame, self)
                    } else if let packet = try? Packet.unpack(frame) {
                        self.inboundHandler?(packet, self)
                    }
                }
            }

            if let error = error {
                Reticulum.log("BackboneInterface \(self.name) receive error: \(error)", level: .warning)
                self.isOnline = false
                self.scheduleReconnect()
                return
            }

            if isComplete {
                Reticulum.log("BackboneInterface \(self.name) connection closed by remote, reconnecting…",
                              level: .warning)
                self.isOnline = false
                self.scheduleReconnect()
                return
            }

            self.beginReceiveLoop()
        }
    }
}
