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
    public private(set) var isOnline: Bool = false

    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = Constants.defaultIfacSize

    public private(set) var rxBytes: Int = 0
    public private(set) var txBytes: Int = 0

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
        stopped = false
        reconnectCount = 0
        connect()
    }

    public func stop() {
        stopped = true
        reconnectTimer?.cancel()
        reconnectTimer = nil
        connection?.cancel()
        connection = nil
        isOnline = false
    }

    public func send(_ packet: Packet) throws {
        guard let connection, isOnline else { return }
        let raw = try packet.pack()
        let framed = HDLC.frame(wrapIfac(raw))
        txBytes += raw.count
        connection.send(content: framed, completion: .contentProcessed { _ in })
    }

    private func connect() {
        guard !stopped else { return }
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let conn = NWConnection(to: endpoint, using: .tcp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.reconnectCount = 0
                self.isOnline = true
                self.beginReceiveLoop()
            case .failed, .cancelled:
                self.isOnline = false
                guard !self.stopped else { return }
                if let max = self.maxReconnectTries, self.reconnectCount >= max { return }
                self.scheduleReconnect()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func scheduleReconnect() {
        reconnectCount += 1
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + reconnectWait)
        timer.setEventHandler { [weak self] in
            guard let self, !self.stopped else { return }
            self.connect()
        }
        timer.resume()
        reconnectTimer?.cancel()
        reconnectTimer = timer
    }

    private func beginReceiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let frames = self.decoder.feed(data)
                for frame in frames {
                    self.rxBytes += frame.count
                    if let h = self.rawInboundHandler {
                        h(frame, self)
                    } else if let packet = try? Packet.unpack(frame) {
                        self.inboundHandler?(packet, self)
                    }
                }
            }
            if error != nil || isComplete {
                self.isOnline = false
                if !self.stopped {
                    self.scheduleReconnect()
                }
                return
            }
            self.beginReceiveLoop()
        }
    }
}
