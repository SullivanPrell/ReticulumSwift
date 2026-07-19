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
    public private(set) var isOnline: Bool = false

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

    public private(set) var rxBytes: Int = 0
    public private(set) var txBytes: Int = 0

    private var connection: NWConnection?
    private let queue: DispatchQueue
    private let decoder = HDLC.FrameDecoder()

    /// Python `TCPClientInterface.__str__` returns `"TCPInterface[Client on <host>:<port>]"`.
    /// rnstatus filters interfaces whose name starts with "TCPInterface[Client".
    public var displayName: String { "TCPInterface[Client on \(host):\(port)]" }

    public init(name: String, host: String, port: UInt16) {
        self.name = name
        self.host = host
        self.port = port
        self.queue = DispatchQueue(label: "ReticulumSwift.TCPClientInterface.\(name)")
    }

    public func start() throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let connection = NWConnection(to: endpoint, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isOnline = true
                Reticulum.log("Interface \(self.name) is up", level: .verbose)
                self.beginReceiveLoop()
            case .failed(let err):
                self.isOnline = false
                Reticulum.log("Interface \(self.name) failed: \(err)", level: .debug)
            case .cancelled:
                self.isOnline = false
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    public func stop() {
        connection?.cancel()
        connection = nil
        isOnline = false
    }

    public func send(_ packet: Packet) throws {
        guard let connection, isOnline else { return }
        let raw = try packet.pack()
        let framed = HDLC.frame(wrapIfac(raw))
        txBytes += raw.count   // Python counts raw (unframed) bytes
        connection.send(content: framed, completion: .contentProcessed { _ in })
    }

    private func beginReceiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let frames = self.decoder.feed(data, hwMtu: self.hwMtu, ifacSize: self.ifacSize)
                for frame in frames {
                    self.rxBytes += frame.count   // Python counts unframed payload bytes
                    if let h = self.rawInboundHandler {
                        h(frame, self)
                    } else if let packet = try? Packet.unpack(frame) {
                        self.inboundHandler?(packet, self)
                    }
                }
            }
            if error != nil || isComplete {
                self.isOnline = false
                return
            }
            self.beginReceiveLoop()
        }
    }
}
