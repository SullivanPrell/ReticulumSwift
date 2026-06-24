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
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = Constants.defaultIfacSize

    public private(set) var rxBytes: Int = 0
    public private(set) var txBytes: Int = 0

    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue: DispatchQueue

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
                conn.start(queue: self?.queue ?? .main)
                self?.beginReceiveLoop(on: conn)
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
            if error == nil { self.beginReceiveLoop(on: conn) }
        }
    }
}
