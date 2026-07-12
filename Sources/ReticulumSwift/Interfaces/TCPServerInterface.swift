import Foundation
import Network

/// Listens for incoming TCP connections from other Reticulum nodes.
///
/// Wire-compatible with `RNS.Interfaces.TCPServerInterface` (Python).
///
/// Each accepted connection spawns a `TCPServerClientInterface` which is
/// registered with Transport as a distinct routing endpoint — matching Python's
/// per-connection `TCPServerInterfaceClient` model.  The server itself is NOT a
/// routing endpoint (`isRoutingEndpoint == false`); only the spawned clients are.
public final class TCPServerInterface: Interface {
    public let name: String
    public let port: UInt16
    public private(set) var bitrate: Int = 10_000_000
    public private(set) var isOnline: Bool = false

    // Python TCPServerInterface: HW_MTU = 262144, AUTOCONFIGURE_MTU = True
    public let hwMtu: Int? = 262_144
    public let autoconfigureMtu: Bool = true

    // Not a routing endpoint — spawned clients are registered separately.
    public var isRoutingEndpoint: Bool { false }

    // IFAC settings inherited by spawned clients.
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = Constants.defaultIfacSize

    // Unused for the server itself (clients use their own handlers).
    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?
    public var recursivePrs: Bool = false
    public var announcesFromInternal: Bool = true

    /// Called by Transport when a new client connects. Transport registers the sub-interface.
    public var onClientConnected: ((any Interface) -> Void)?
    /// Called by Transport when a client disconnects. Transport deregisters the sub-interface.
    public var onClientDisconnected: ((any Interface) -> Void)?

    public var rxBytes: Int = 0
    public var txBytes: Int = 0

    /// Python `TCPServerInterface.__str__` returns `"TCPInterface[Server on 0.0.0.0:<port>]"`.
    public var displayName: String { "TCPInterface[Server on 0.0.0.0:\(port)]" }

    /// Number of currently-connected clients. Used by buildInterfaceStats for rnstatus.
    public var clientCount: Int {
        lock.lock(); defer { lock.unlock() }
        return spawned.count
    }

    private var listener: NWListener?
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var spawned: [SpawnedClient] = []
    private var clientCounter = 0

    public init(name: String, port: UInt16) {
        self.name = name
        self.port = port
        self.queue = DispatchQueue(label: "ReticulumSwift.TCPServerInterface.\(name)", attributes: .concurrent)
    }

    public func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw InterfaceError.invalidConfiguration("invalid port \(port)")
        }
        let listener = try NWListener(using: .tcp, on: nwPort)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isOnline = true
                Reticulum.log("Interface \(self.name) listening on port \(self.port)", level: .verbose)
            case .failed(let err):
                self.isOnline = false
                Reticulum.log("Interface \(self.name) listener failed: \(err)", level: .error)
            case .cancelled:
                self.isOnline = false
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let all = spawned
        spawned.removeAll()
        lock.unlock()
        for c in all { c.cancel() }
        isOnline = false
    }

    /// Broadcast to ALL connected clients. Used only when we need to send to every peer
    /// (e.g. the PosixTCPServer shared-instance model). Transport routing uses the
    /// per-client `TCPServerClientInterface.send()` instead.
    public func send(_ packet: Packet) throws {
        let raw = try packet.pack()
        let framed = HDLC.frame(wrapIfac(raw))
        if !raw.isEmpty { txBytes += raw.count }
        lock.lock()
        let clients = spawned
        lock.unlock()
        for c in clients { c.send(framed) }
    }

    // MARK: - Connection acceptance

    private func accept(_ conn: NWConnection) {
        lock.lock()
        clientCounter += 1
        let clientIndex = clientCounter
        lock.unlock()

        let clientName = "\(name)[client-\(clientIndex)]"
        Reticulum.log("Accepted TCP connection \(clientIndex) on \(name)", level: .verbose)

        // Create a client interface before starting the connection so the
        // onFrame callback can reference it.
        let clientIface = TCPServerClientInterface(
            name: clientName,
            parentServer: self
        )

        let spawned = SpawnedClient(
            conn: conn,
            queue: DispatchQueue(label: "ReticulumSwift.TCPServerInterface.\(name).\(clientIndex)", target: queue),
            onFrame: { [weak clientIface] frame in
                guard let ci = clientIface else { return }
                ci.rxBytes += frame.count
                if let h = ci.rawInboundHandler {
                    h(frame, ci)
                } else if let packet = try? Packet.unpack(frame) {
                    ci.inboundHandler?(packet, ci)
                }
            },
            onClose: { [weak self, weak clientIface] client in
                guard let self, let ci = clientIface else { return }
                Reticulum.log("TCP connection closed on \(self.name)", level: .verbose)
                ci.isOnline = false
                self.lock.lock()
                self.spawned.removeAll { $0 === client }
                self.lock.unlock()
                self.onClientDisconnected?(ci)
            }
        )

        clientIface.spawnedClient = spawned

        lock.lock()
        self.spawned.append(spawned)
        lock.unlock()

        spawned.start()

        // Register the sub-interface with Transport.
        onClientConnected?(clientIface)
    }
}

// MARK: - TCPServerClientInterface

/// A single accepted connection on a `TCPServerInterface`.
///
/// Mirrors Python's per-connection `TCPServerInterfaceClient` which is registered
/// with Transport as an independent Interface.
public final class TCPServerClientInterface: Interface {
    public let name: String
    public var bitrate: Int = 10_000_000
    public internal(set) var isOnline: Bool = true

    public let hwMtu: Int? = 262_144
    public let autoconfigureMtu: Bool = true

    // Fully a routing endpoint.
    public var isRoutingEndpoint: Bool { true }

    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int

    public var rxBytes: Int = 0
    public var txBytes: Int = 0

    public var displayName: String { "TCPInterface[Client on \(name)]" }

    // Back-reference to parent server (for IFAC inheritance).
    private weak var parentServer: TCPServerInterface?
    // The underlying TCP connection.
    fileprivate weak var spawnedClient: SpawnedClient?

    init(name: String, parentServer: TCPServerInterface) {
        self.name = name
        self.parentServer = parentServer
        // Inherit IFAC settings from parent server.
        self.ifacIdentity = parentServer.ifacIdentity
        self.ifacKey      = parentServer.ifacKey
        self.ifacSize     = parentServer.ifacSize
    }

    public func start() throws { }  // started by the parent server

    public func stop() {
        spawnedClient?.cancel()
        isOnline = false
    }

    public func send(_ packet: Packet) throws {
        guard isOnline, let client = spawnedClient else { return }
        let raw = try packet.pack()
        let framed = HDLC.frame(wrapIfac(raw))
        if !raw.isEmpty { txBytes += raw.count }
        client.send(framed)
    }
}

// MARK: - Error

private enum InterfaceError: Error {
    case invalidConfiguration(String)
}

// MARK: - SpawnedClient (shared between server and client interface)

final class SpawnedClient {
    private let conn: NWConnection
    private let queue: DispatchQueue
    private let onFrame: (Data) -> Void
    private let onClose: (SpawnedClient) -> Void
    private let decoder = HDLC.FrameDecoder()

    init(conn: NWConnection, queue: DispatchQueue,
         onFrame: @escaping (Data) -> Void,
         onClose: @escaping (SpawnedClient) -> Void) {
        self.conn = conn
        self.queue = queue
        self.onFrame = onFrame
        self.onClose = onClose
    }

    func start() {
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.receive()
            case .failed, .cancelled:
                self.onClose(self)
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    func cancel() {
        conn.cancel()
    }

    func send(_ framed: Data) {
        conn.send(content: framed, completion: .contentProcessed { _ in })
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                for frame in self.decoder.feed(data) {
                    self.onFrame(frame)
                }
            }
            if error != nil || isComplete {
                self.onClose(self)
                return
            }
            self.receive()
        }
    }
}
