import Foundation
import Network

/// Bidirectional UDP transport for Reticulum packets, wire-compatible
/// with `RNS.Interfaces.UDPInterface`. One datagram carries exactly one
/// raw `Packet` — no HDLC framing.
///
/// Provide a `listenPort` to receive datagrams, and a
/// `forwardHost`/`forwardPort` to address outbound traffic. Either
/// direction is optional, but at least one must be configured.
public final class UDPInterface: Interface {
    public let name: String
    public let listenPort: UInt16?
    public let forwardHost: String?
    public let forwardPort: UInt16?
    public private(set) var bitrate: Int = 10_000_000
    public private(set) var isOnline: Bool = false

    // Python UDPInterface: HW_MTU = 1064
    public let hwMtu: Int? = 1_064

    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?
    public var recursivePrs: Bool = false
    public var announcesFromInternal: Bool = true
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = Constants.defaultIfacSize

    public private(set) var rxBytes: Int = 0
    public private(set) var txBytes: Int = 0

    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue: DispatchQueue
    /// Inbound connections accepted by the listener. Retained so stop() can
    /// cancel them (otherwise every inbound peer leaks its connection + receive
    /// loop) and pruned when their receive loop ends. Guarded by `connLock`
    /// (newConnectionHandler runs on `queue`, stop() on the caller thread).
    private var inboundConnections: [NWConnection] = []
    private let connLock = NSLock()

    /// Python `UDPInterface.__str__` returns `"UDPInterface[<name>/<ip>:<port>]"`.
    public var displayName: String {
        let ip = "0.0.0.0"
        let port = listenPort ?? forwardPort ?? 0
        return "UDPInterface[\(name)/\(ip):\(port)]"
    }

    public init(
        name: String,
        listenPort: UInt16? = nil,
        forwardHost: String? = nil,
        forwardPort: UInt16? = nil
    ) {
        self.name = name
        self.listenPort = listenPort
        self.forwardHost = forwardHost
        self.forwardPort = forwardPort
        self.queue = DispatchQueue(label: "ReticulumSwift.UDPInterface.\(name)")
    }

    public func start() throws {
        if let listenPort, let port = NWEndpoint.Port(rawValue: listenPort) {
            let listener = try NWListener(using: .udp, on: port)
            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { conn.cancel(); return }
                self.connLock.lock()
                self.inboundConnections.append(conn)
                self.connLock.unlock()
                conn.start(queue: self.queue)
                self.beginReceiveLoop(on: conn)
            }
            listener.start(queue: queue)
            self.listener = listener
        }

        if let forwardHost, let forwardPort, let port = NWEndpoint.Port(rawValue: forwardPort) {
            let connection = NWConnection(
                to: .hostPort(host: NWEndpoint.Host(forwardHost), port: port),
                using: .udp
            )
            connection.start(queue: queue)
            self.connection = connection
        }

        isOnline = true
    }

    public func stop() {
        listener?.cancel(); listener = nil
        connection?.cancel(); connection = nil
        connLock.lock()
        let inbound = inboundConnections
        inboundConnections.removeAll()
        connLock.unlock()
        for c in inbound { c.cancel() }
        isOnline = false
    }

    public func send(_ packet: Packet) throws {
        guard let connection else { return }
        let raw = try packet.pack()
        txBytes += raw.count
        connection.send(content: wrapIfac(raw), completion: .contentProcessed { _ in })
    }

    private func beginReceiveLoop(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.rxBytes += data.count
                if let h = self.rawInboundHandler {
                    h(data, self)
                } else if let packet = try? Packet.unpack(data) {
                    self.inboundHandler?(packet, self)
                }
            }
            if error == nil {
                self.beginReceiveLoop(on: conn)
            } else {
                // Receive loop ended — drop and cancel this inbound connection
                // so it doesn't accumulate.
                self.connLock.lock()
                self.inboundConnections.removeAll { $0 === conn }
                self.connLock.unlock()
                conn.cancel()
            }
        }
    }
}
