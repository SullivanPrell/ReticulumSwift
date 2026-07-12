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
    private var isStopped: Bool = false

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
        isStopped = false
        reconnectAttempts = 0
        openConnection()
    }

    public func stop() {
        isStopped = true
        isOnline = false
        connection?.cancel()
        connection = nil
    }

    // MARK: - Packet send

    public func send(_ packet: Packet) throws {
        guard let connection, isOnline else { return }
        let raw = try packet.pack()
        let framed = framePacketBytes(raw)
        txBytes += raw.count
        connection.send(content: framed, completion: .contentProcessed { _ in })
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
        guard !isStopped else { return }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let conn = NWConnection(to: endpoint, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self, !self.isStopped else { return }
            switch state {
            case .ready:
                self.isOnline = true
                self.reconnectAttempts = 0
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
        guard !isStopped else { return }

        if let maxTries = maxReconnectTries, reconnectAttempts >= maxTries {
            Reticulum.log("BackboneInterface \(name) reached max reconnect tries (\(maxTries)), giving up.",
                          level: .error)
            return
        }

        reconnectAttempts += 1
        Reticulum.log("BackboneInterface \(name) scheduling reconnect in \(reconnectWait)s (attempt \(reconnectAttempts))",
                      level: .verbose)

        queue.asyncAfter(deadline: .now() + reconnectWait) { [weak self] in
            guard let self, !self.isStopped else { return }
            self.openConnection()
        }
    }

    private func beginReceiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, !self.isStopped else { return }

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
