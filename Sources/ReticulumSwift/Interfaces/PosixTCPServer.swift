import Foundation
import Darwin

/// A TCP server bound with a raw POSIX socket — deliberately does NOT set SO_REUSEADDR.
///
/// On macOS, NWListener sets SO_REUSEADDR internally. That allows Python's
/// `LocalServerInterface` (which also uses SO_REUSEADDR) to rebind the same port,
/// making Python become the shared-instance server instead of a client.
/// By using a raw socket without SO_REUSEADDR, we hold the port exclusively:
/// Python's `bind()` call will fail with EADDRINUSE → Python falls back to
/// `LocalClientInterface` (client mode) and does NOT synthesize interfaces.
///
/// Used only for the shared-instance port (37428). All other server interfaces
/// can continue to use `TCPServerInterface` + `NWListener`.
public final class PosixTCPServer: Interface, LocalClientServingInterface {
    public let name: String
    public let port: UInt16
    public private(set) var bitrate: Int = 1_000_000_000
    public private(set) var isOnline: Bool = false

    public let hwMtu: Int? = 262_144
    public let autoconfigureMtu: Bool = true

    // Not a mesh routing endpoint: `send()` already fans out to every attached
    // local client directly, and local-client delivery is handled by
    // Transport's dedicated `localClientServingInterfaces` announce forward
    // (independent of transportEnabled). Excluding it here mirrors
    // TCPServerInterface's listener/spawned-client split and prevents
    // double-delivery to local clients when transportEnabled is also true.
    public var isRoutingEndpoint: Bool { false }

    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = Constants.defaultIfacSize

    public private(set) var rxBytes: Int = 0
    public private(set) var txBytes: Int = 0

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue: DispatchQueue
    /// Serial queue that all inbound frame deliveries funnel through, so the
    /// shared `rxBytes` counter and the (non-thread-safe) inbound handler are
    /// never invoked concurrently by multiple client connections.
    private let deliveryQueue = DispatchQueue(label: "ReticulumSwift.PosixTCPServer.delivery")
    private let lock = NSLock()
    private var clients: [PosixClient] = []

    /// Python `LocalServerInterface.__str__` returns `"Shared Instance[<port>]"`.
    /// Shown in rnstatus output; distinct from the client-side "LocalInterface[...]".
    public var displayName: String { "\(name)[\(port)]" }

    /// Number of currently-connected clients. Used by buildInterfaceStats for rnstatus.
    public var clientCount: Int {
        lock.lock(); defer { lock.unlock() }
        return clients.count
    }

    public init(name: String, port: UInt16) {
        self.name = name
        self.port = port
        self.queue = DispatchQueue(label: "ReticulumSwift.PosixTCPServer.\(name)", attributes: .concurrent)
    }

    public func start() throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw PosixError.errno(Darwin.errno, "socket()")
        }

        // Prevent SIGPIPE on writes to closed connections
        var one: Int32 = 1
        Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        // Explicitly do NOT set SO_REUSEADDR — this is intentional.
        // Without it, Python's SO_REUSEADDR bind attempt fails → client mode.

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        // Bind to 127.0.0.1, not INADDR_ANY. This is intentional:
        // on macOS, SO_REUSEADDR lets a new socket rebind 0.0.0.0:port while we hold it,
        // but it cannot rebind 127.0.0.1:port when we already hold that exact address.
        // Python's LocalServerInterface also binds to 127.0.0.1, so our binding blocks it.
        Darwin.inet_aton("127.0.0.1", &addr.sin_addr)

        let bindRC = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRC == 0 else {
            Darwin.close(fd)
            throw PosixError.errno(Darwin.errno, "bind(:\(port))")
        }

        guard Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            throw PosixError.errno(Darwin.errno, "listen()")
        }

        listenFD = fd
        isOnline = true

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        acceptSource = src
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        isOnline = false
        lock.lock()
        let all = clients
        clients.removeAll()
        lock.unlock()
        for c in all { c.close() }
    }

    public func send(_ packet: Packet) throws {
        let raw = try packet.pack()
        let framed = HDLC.frame(wrapIfac(raw))
        txBytes += raw.count
        lock.lock()
        let all = clients
        lock.unlock()
        for c in all { c.write(framed) }
    }

    // MARK: - Accept loop

    private func acceptOne() {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.accept(listenFD, $0, &addrLen)
            }
        }
        guard clientFD >= 0 else { return }

        let client = PosixClient(
            fd: clientFD,
            queue: DispatchQueue(label: "ReticulumSwift.PosixTCPServer.client", target: queue),
            onFrame: { [weak self] data in
                guard let self else { return }
                // Funnel every client's delivery through one serial queue so the
                // shared counter and inbound handler never run concurrently.
                self.deliveryQueue.async {
                    self.rxBytes += data.count
                    if let h = self.rawInboundHandler {
                        h(data, self)
                    } else if let p = try? Packet.unpack(data) {
                        self.inboundHandler?(p, self)
                    }
                }
            },
            onClose: { [weak self] c in
                guard let self else { return }
                self.lock.lock()
                self.clients.removeAll { $0 === c }
                self.lock.unlock()
            }
        )
        lock.lock()
        clients.append(client)
        lock.unlock()
        client.start()
    }

    public enum PosixError: Error {
        case errno(Int32, String)
        var localizedDescription: String {
            if case .errno(let n, let ctx) = self {
                return "\(ctx): \(String(cString: strerror(n)))"
            }
            return "PosixError"
        }
    }
}

// MARK: - Per-connection client

private final class PosixClient {
    private let fd: Int32
    private let queue: DispatchQueue
    private let onFrame: (Data) -> Void
    private let onClose: (PosixClient) -> Void
    private let decoder = HDLC.FrameDecoder()
    private var io: DispatchIO?

    init(fd: Int32, queue: DispatchQueue,
         onFrame: @escaping (Data) -> Void,
         onClose: @escaping (PosixClient) -> Void) {
        self.fd = fd
        self.queue = queue
        self.onFrame = onFrame
        self.onClose = onClose
    }

    func start() {
        var one: Int32 = 1
        Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        let channel = DispatchIO(type: .stream, fileDescriptor: fd, queue: queue) { _ in
            Darwin.close(self.fd)
        }
        channel.setLimit(lowWater: 1)
        io = channel
        readLoop(channel)
    }

    private func readLoop(_ channel: DispatchIO) {
        channel.read(offset: 0, length: 4096, queue: queue) { [weak self] done, dispatchData, _ in
            guard let self else { return }
            if let dd = dispatchData, !dd.isEmpty {
                for frame in self.decoder.feed(Data(dd)) {
                    self.onFrame(frame)
                }
            }
            if done {
                self.io = nil
                self.onClose(self)
                return
            }
            self.readLoop(channel)
        }
    }

    func write(_ data: Data) {
        guard let channel = io else { return }
        let dd = data.withUnsafeBytes { DispatchData(bytes: $0) }
        channel.write(offset: 0, data: dd, queue: queue) { _, _, _ in }
    }

    func close() {
        io?.close()
        io = nil
    }
}
