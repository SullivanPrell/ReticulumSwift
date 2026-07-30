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
    /// Per-interface mutable configuration (mode, announce rate control, ingress/egress
    /// control, the `ic_*` tunables). One stored property satisfies the whole settable set;
    /// see `InterfaceState` and `swift_devel/bugs/025-*.md`.
    public let interfaceState = InterfaceState()
    public let name: String
    public let listenPort: UInt16?
    public let forwardHost: String?
    public let forwardPort: UInt16?
    public var bitrate: Int = 10_000_000
    private let onlineFlag = LockedFlag(false)
    public private(set) var isOnline: Bool {
        get { onlineFlag.value }
        set { onlineFlag.value = newValue }
    }

    // Python UDPInterface: HW_MTU = 1064
    public let hwMtu: Int? = 1_064

    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?
    public var recursivePrs: Bool = false
    public var announcesFromInternal: Bool = true
    /// Mirrors Python's `Interface.announces_to_internal` (RNS 1.4.1).
    public var announcesToInternal: Bool? = nil
    /// Mirrors Python's `Interface.gravity` (RNS 1.4.1).
    public var gravity: Int = InterfaceMode.defaultGravity
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = Constants.defaultIfacSize

    /// Lock-guarded — written from this interface's I/O queue while the UI
    /// and status reporting read from another thread. See `InterfaceCounters`.
    private let counters = InterfaceCounters()
    public var rxBytes: Int { counters.rxBytes }
    public var txBytes: Int { counters.txBytes }

    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue: DispatchQueue
    /// Inbound connections accepted by the listener. Retained so stop() can
    /// cancel them (otherwise every inbound peer leaks its connection + receive
    /// loop) and pruned when their receive loop ends. Guarded by `connLock`
    /// (newConnectionHandler runs on `queue`, stop() on the caller thread).
    private var inboundConnections: [NWConnection] = []
    private let connLock = NSLock()

    /// Python `UDPInterface.__str__` (`UDPInterface.py:131-132`):
    /// `"UDPInterface["+self.name+"/"+self.bind_ip+":"+str(self.bind_port)+"]"`, where
    /// `bind_ip` is the configured `listen_ip` (`UDPInterface.py:63`, `:91`). Hardcoding
    /// `0.0.0.0` here made a loopback-bound Swift interface report a different name — and
    /// so a different `Interface.hash` — than the Python interface beside it.
    public var displayName: String {
        let ip = bindIP.contains(":") ? "[\(bindIP)]" : bindIP
        let port = listenPort ?? forwardPort ?? 0
        return "UDPInterface[\(name)/\(ip):\(port)]"
    }

    /// The configured `listen_ip`. Python's `bind_ip`; reporting-only here, since
    /// `NWListener` binds every address.
    public let bindIP: String

    public init(
        name: String,
        listenPort: UInt16? = nil,
        forwardHost: String? = nil,
        forwardPort: UInt16? = nil,
        bindIP: String = "0.0.0.0"
    ) {
        self.name = name
        self.listenPort = listenPort
        self.forwardHost = forwardHost
        self.forwardPort = forwardPort
        self.bindIP = bindIP
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
        counters.addTx(bytes: raw.count)
        connection.send(content: wrapIfac(raw), completion: .contentProcessed { _ in })
    }

    private func beginReceiveLoop(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.counters.addRx(bytes: data.count)
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
