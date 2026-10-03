//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Darwin
import Foundation

/// A TCP server bound with a raw POSIX socket—deliberately doesn't set SO_REUSEADDR.
///
/// On macOS, NWListener sets SO_REUSEADDR internally. That allows Python's
/// `LocalServerInterface` (which also uses SO_REUSEADDR) to rebind the same port,
/// making Python become the shared-instance server instead of a client.
/// By using a raw socket without SO_REUSEADDR, this holds the port exclusively:
/// Python's `bind()` call fails with EADDRINUSE → Python falls back to
/// `LocalClientInterface` (client mode) and doesn't synthesize interfaces.
///
/// Used only for the shared-instance port (37428). All other server interfaces
/// can continue to use `TCPServerInterface` + `NWListener`.
///
/// This is Python's `LocalServerInterface`. Each connection it accepts becomes a
/// `LocalServerClientInterface` of its own, which `onClientConnected` hands to the transport,
/// as `incoming_connection` adds a `LocalClientInterface` to `Transport.interfaces` and
/// `Transport.local_client_interfaces` (`LocalInterface.py:447-460`). The server itself sends
/// nothing.
public final class PosixTCPServer: Interface, MtuAutoconfiguringInterface {
  /// Per-interface mutable configuration (mode, announce rate control, ingress/egress
  /// control, the `ic_*` tunables).
  ///
  /// One stored property satisfies the whole settable set;
  /// see `InterfaceState` and `swift_devel/bugs/025-*.md`.
  public let interfaceState = InterfaceState()

  /// Interface name as it appears in configuration and status output.
  public let name: String
  /// TCP port the server listens on.
  public let port: UInt16
  /// Nominal interface bitrate in bits per second.
  public var bitrate: Int = 1_000_000_000
  private let onlineFlag = LockedFlag(false)
  /// Whether the interface is up and able to carry traffic.
  public private(set) var isOnline: Bool {
    get { onlineFlag.value }
    set { onlineFlag.value = newValue }
  }

  /// Hardware maximum transmission unit in bytes.
  public var hwMtu: Int? = 262_144
  /// Whether the link maximum transmission unit is negotiated with the peer.
  public let autoconfigureMtu: Bool = true

  // Not a mesh routing endpoint: it sends nothing, and Transport reaches the local clients
  // through their own connections (`LocalServerClientInterface`), which mirrors
  // TCPServerInterface's listener/spawned-client split.
  /// Whether Transport routes packets and forwards announces through this interface.
  public var isRoutingEndpoint: Bool { false }

  /// Called with each accepted connection's interface, before the server reads from it.
  public var onClientConnected: ((any Interface) -> Void)?
  /// Called with a connection's interface once the client hangs up.
  public var onClientDisconnected: ((any Interface) -> Void)?

  /// Unused: frames arrive on the interface of the connection that carried them.
  public var inboundHandler: ((Packet, any Interface) -> Void)?
  /// Unused: frames arrive on the interface of the connection that carried them.
  public var rawInboundHandler: ((Data, any Interface) -> Void)?
  /// Identity authenticating this interface under IFAC, or `nil` when IFAC is off.
  public var ifacIdentity: Identity?
  /// Derived IFAC key used to sign and verify frames.
  public var ifacKey: Data?
  /// IFAC authentication field size in bytes.
  public var ifacSize: Int = Constants.defaultIfacSize

  /// Lock-guarded—written from every connection's I/O while the UI
  /// and status reporting read from another thread.
  ///
  /// See `InterfaceCounters`.
  private let counters = InterfaceCounters()
  /// Total bytes received across all connections.
  ///
  /// Each connection also adds what it receives to its parent (`LocalInterface.py:205-206`).
  public var rxBytes: Int { counters.rxBytes }
  /// Total bytes transmitted across all connections.
  public var txBytes: Int { counters.txBytes }

  fileprivate func noteRx(bytes: Int) { counters.addRx(bytes: bytes) }
  fileprivate func noteTx(bytes: Int) { counters.addTx(bytes: bytes) }

  private var listenFD: Int32 = -1
  private var acceptSource: DispatchSourceRead?
  private let queue: DispatchQueue
  /// Serial queue that all inbound frame deliveries funnel through, so the
  /// inbound handlers are never invoked concurrently by multiple client connections.
  private let deliveryQueue = DispatchQueue(label: "ReticulumSwift.PosixTCPServer.delivery")
  private let lock = NSLock()
  private var clients: [LocalServerClientInterface] = []

  /// Descriptors this server has accepted, for tests that assert the socket options actually
  /// landed.
  ///
  /// Unlike the Network.framework paths, a POSIX descriptor has an authoritative
  /// readback—`getsockopt`—so `bugs/023` is verifiable here rather than only structural.
  private var acceptedDescriptors: [Int32] = []
  var lastAcceptedDescriptorForTesting: Int32? {
    lock.lock()
    defer { lock.unlock() }
    return acceptedDescriptors.last
  }
  var acceptedDescriptorHandlerForTesting: ((Int32) -> Void)?
  /// Called each time a client's connection reports that it ended.
  var clientDetachedHandlerForTesting: (() -> Void)?

  /// Python `LocalServerInterface.__str__` (`LocalInterface.py:496-498`) returns the literal
  /// `"Shared Instance["+str(bind_port)+"]"`.
  ///
  /// Shown in rnstatus output; distinct from the
  /// client-side `"LocalInterface[…]"`.
  ///
  /// `"Shared Instance"` is hardcoded here, not read from `name`. Python's
  /// `LocalServerInterface` sets `self.name = "Reticulum"` (`LocalInterface.py:391`) and its
  /// `__str__` ignores it entirely, so building the string from `name` made this correct only
  /// while the one caller happened to pass `name: "Shared Instance"`
  /// (`InstanceConnection.swift:208`)—correct by coincidence at a single call site, which is
  /// the `bugs/013` shape. Found by the enumerate-every-conformer test in `bugs/022`; not in
  /// the audit's list of nine.
  public var displayName: String { "Shared Instance[\(port)]" }

  /// This class is Python's `LocalServerInterface`; only the Swift name differs.
  ///
  /// Reported
  /// verbatim in the stats payload, where a Python `rnstatus -d` prints it and would
  /// otherwise show "PosixTCPServer", an interface kind that doesn't exist in RNS.
  public var statsTypeName: String { "LocalServerInterface" }

  /// Python hardcodes `self.name = "Reticulum"` on `LocalServerInterface`
  /// (RNS/Interfaces/LocalInterface.py:391), while `__str__` stays "Shared Instance[…]".
  ///
  /// Swift uses `name` to identify the interface internally, so the published short name
  /// is set here rather than by renaming the interface.
  public var statsShortName: String { "Reticulum" }

  /// Number of connected clients, Python's `LocalServerInterface.clients`.
  ///
  /// Used by buildInterfaceStats for rnstatus.
  public var clientCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return clients.count
  }

  /// Creates a server interface listening on a TCP port.
  public init(name: String, port: UInt16) {
    self.name = name
    self.port = port
    self.queue = DispatchQueue(
      label: "ReticulumSwift.PosixTCPServer.\(name)", attributes: .concurrent)
  }

  /// Brings the interface online.
  public func start() throws {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw PosixError.errno(Darwin.errno, "socket()")
    }

    // Prevent SIGPIPE on writes to closed connections
    var one: Int32 = 1
    Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

    // Explicitly don't set SO_REUSEADDR—this is intentional.
    // Without it, Python's SO_REUSEADDR bind attempt fails → client mode.

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    // Bind to 127.0.0.1, not INADDR_ANY. This is intentional:
    // on macOS, SO_REUSEADDR lets a new socket rebind 0.0.0.0:port while this socket holds it,
    // but it can't rebind 127.0.0.1:port when this socket already holds that exact address.
    // Python's LocalServerInterface also binds to 127.0.0.1, so this binding blocks it.
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

  /// Takes the interface offline and releases its resources.
  public func stop() {
    acceptSource?.cancel()
    acceptSource = nil
    isOnline = false
    lock.lock()
    let all = clients
    clients.removeAll()
    lock.unlock()
    for client in all { client.stop() }
  }

  /// Sends nothing.
  ///
  /// `LocalServerInterface.process_outgoing` is `pass` (`LocalInterface.py:462-463`): every
  /// packet for a local client goes out through that client's own connection. This used to
  /// write to every connection, so every client received what the shared instance sent any
  /// one of them.
  public func send(_ packet: Packet) throws {}

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

    // Python sets `TCP_NODELAY` on every socket its shared-instance server accepts
    // (`LocalInterface.py:98-100`)—the accepted-socket half of `bugs/023`, in the POSIX
    // server rather than the Network.framework one. This port set only `SO_NOSIGPIPE`, so
    // small control frames sat behind Nagle's delayed-ACK timer on every shared-instance
    // client. Found while building `RNSSocketOptions`; not in `bugs/023` as filed.
    RNSSocketOptions.applyLocalOptions(toFileDescriptor: clientFD)
    lock.lock()
    acceptedDescriptors.append(clientFD)
    lock.unlock()
    acceptedDescriptorHandlerForTesting?(clientFD)

    // `interface_name = str(handler.client_address[1])` (`LocalInterface.py:448`).
    let peerHost = String(cString: inet_ntoa(clientAddr.sin_addr))
    let peerPort = UInt16(bigEndian: clientAddr.sin_port)
    let spawned = LocalServerClientInterface(
      name: String(peerPort), parentServer: self, peerHost: peerHost, peerPort: peerPort)
    let connection = PosixClient(
      fd: clientFD,
      queue: DispatchQueue(label: "ReticulumSwift.PosixTCPServer.client", target: queue),
      onFrame: { [weak self, weak spawned] data in
        guard let self, let spawned else { return }
        // Funnel every client's delivery through one serial queue so the
        // inbound handlers never run concurrently.
        self.deliveryQueue.async { spawned.receive(data) }
      },
      onClose: { [weak self, weak spawned] _ in
        guard let self, let spawned else { return }
        spawned.markOffline()
        self.lock.lock()
        self.clients.removeAll { $0 === spawned }
        self.lock.unlock()
        self.onClientDisconnected?(spawned)
        self.clientDetachedHandlerForTesting?()
      }
    )
    spawned.connection = connection
    lock.lock()
    clients.append(spawned)
    lock.unlock()
    // Registered before the first read, so no frame arrives ahead of its handler.
    onClientConnected?(spawned)
    connection.start()
  }

  /// Errors raised by the POSIX socket server.
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

// MARK: - Spawned connection interface

/// One connection the shared instance accepted.
///
/// Python's `LocalClientInterface` built from a connected socket (`LocalInterface.py:447-460`):
/// named by the client's port, a child of the server, and counted as a local client by
/// `Transport.is_local_client_interface`. It serves exactly one client, so `clientCount` is one
/// while the connection is up.
public final class LocalServerClientInterface: Interface, LocalClientServingInterface,
  SpawnedInterface, MtuAutoconfiguringInterface
{
  /// Per-interface mutable configuration.
  ///
  /// Fresh rather than inherited: Python copies only the direction flags, `bitrate` and
  /// `_force_bitrate` onto the connection (`LocalInterface.py:450-456`).
  public let interfaceState = InterfaceState()

  /// The client's port, as Python names the connection.
  public let name: String
  /// Interface bitrate in bits per second, copied from the server.
  public var bitrate: Int
  private let onlineFlag = LockedFlag(true)
  /// Whether the client is still connected.
  public private(set) var isOnline: Bool {
    get { onlineFlag.value }
    set { onlineFlag.value = newValue }
  }

  /// Hardware maximum transmission unit in bytes (`LocalInterface.py:64`).
  public var hwMtu: Int? = 262_144
  /// Whether `optimise_mtu` sets `hwMtu` from the bitrate (`AUTOCONFIGURE_MTU`).
  public let autoconfigureMtu: Bool = true

  /// Whether Transport routes packets and forwards announces through this interface.
  ///
  /// True: Python's server copies its outbound flag onto each connection
  /// (`LocalInterface.py:450`, `Reticulum.py:403`), so Python's broadcast loops reach every
  /// local client (`Transport.py:1449`).
  public var isRoutingEndpoint: Bool { true }

  /// Called with each packet decoded from the client.
  public var inboundHandler: ((Packet, any Interface) -> Void)?
  /// Called with each frame received before packet decoding.
  public var rawInboundHandler: ((Data, any Interface) -> Void)?
  /// Identity deriving the IFAC key, unused on a shared instance.
  public var ifacIdentity: Identity?
  /// IFAC key, unused on a shared instance.
  public var ifacKey: Data?
  /// IFAC token size in bytes.
  public var ifacSize: Int = Constants.defaultIfacSize

  private let counters = InterfaceCounters()
  /// Unframed bytes received from the client (`LocalInterface.py:205`).
  public var rxBytes: Int { counters.rxBytes }
  /// HDLC-framed bytes sent to the client (`LocalInterface.py:241`).
  public var txBytes: Int { counters.txBytes }

  /// The client's address.
  public let peerHost: String
  /// The client's port.
  public let peerPort: UInt16

  /// `"LocalInterface["+str(self.target_port)+"]"` (`LocalInterface.py:351-353`), the prefix
  /// `rnstatus` hides unless asked for every interface.
  public var displayName: String { "LocalInterface[\(peerPort)]" }
  /// Python builds a plain `LocalClientInterface` for each connection.
  public var statsTypeName: String { "LocalClientInterface" }

  private weak var parentServer: PosixTCPServer?
  /// The shared-instance server that accepted this connection.
  public var spawningInterface: (any Interface)? { parentServer }
  /// One until the client hangs up.
  public var clientCount: Int { isOnline ? 1 : 0 }

  fileprivate var connection: PosixClient?

  init(name: String, parentServer: PosixTCPServer, peerHost: String, peerPort: UInt16) {
    self.name = name
    self.parentServer = parentServer
    self.peerHost = peerHost
    self.peerPort = peerPort
    self.bitrate = parentServer.bitrate
  }

  /// No-op: the server starts reading once the transport has the interface.
  public func start() throws {}

  /// Closes the connection.
  public func stop() {
    isOnline = false
    connection?.close()
  }

  /// Sends `packet` to this client only.
  ///
  /// Counts the framed length here and on the server, as `process_outgoing` does
  /// (`LocalInterface.py:238-243`).
  public func send(_ packet: Packet) throws {
    guard isOnline, let connection else { return }
    let framed = HDLC.frame(wrapIfac(try packet.pack()))
    connection.write(framed)
    counters.addTx(bytes: framed.count)
    parentServer?.noteTx(bytes: framed.count)
  }

  fileprivate func markOffline() { isOnline = false }

  /// One frame from the client, counted here and on the server (`LocalInterface.py:204-206`).
  fileprivate func receive(_ frame: Data) {
    counters.addRx(bytes: frame.count)
    parentServer?.noteRx(bytes: frame.count)
    if let handler = rawInboundHandler {
      handler(frame, self)
    } else if let packet = try? Packet.unpack(frame) {
      inboundHandler?(packet, self)
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
  /// Written by the read handler and by `close()`, read by `write(_:)` on the sender's thread.
  private let ioLock = NSLock()
  private var ioChannel: DispatchIO?
  private var io: DispatchIO? {
    get {
      ioLock.lock()
      defer { ioLock.unlock() }
      return ioChannel
    }
    set {
      ioLock.lock()
      ioChannel = newValue
      ioLock.unlock()
    }
  }

  init(
    fd: Int32, queue: DispatchQueue,
    onFrame: @escaping (Data) -> Void,
    onClose: @escaping (PosixClient) -> Void
  ) {
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
    readUntilClosed(channel)
  }

  /// `dispatch_io_read`'s length for "read until end of file": `SIZE_MAX`.
  private static let untilEndOfFile = Int(bitPattern: UInt(SIZE_MAX))

  /// One read for the life of the connection, as Python's `read_loop` is one `recv` loop that
  /// stops only when `recv` returns nothing (`LocalInterface.py:276-295`).
  ///
  /// A stream read also completes when it has delivered the length it asked for. This loop
  /// asked for 4096 bytes and took that completion for a hang-up, so it dropped every client
  /// after its first 4 KB and discarded everything sent to it afterwards. It also started a
  /// new read on every partial delivery, so a busy client's outstanding reads grew without
  /// bound. Reading until end of file leaves `done` with one meaning: the client hung up, or
  /// the socket failed.
  private func readUntilClosed(_ channel: DispatchIO) {
    channel.read(offset: 0, length: Self.untilEndOfFile, queue: queue) {
      [weak self] done, dispatchData, _ in
      guard let self else { return }
      if let dd = dispatchData, !dd.isEmpty {
        for frame in self.decoder.feed(Data(dd)) {
          self.onFrame(frame)
        }
      }
      if done {
        self.io = nil
        self.onClose(self)
      }
    }
  }

  func write(_ data: Data) {
    guard let channel = io else { return }
    let dd = data.withUnsafeBytes { DispatchData(bytes: $0) }
    channel.write(offset: 0, data: dd, queue: queue) { _, _, _ in }
  }

  /// Hangs up on the client.
  ///
  /// `.stop` cancels the outstanding read. Without it `DispatchIO` waits for pending
  /// operations, and the read ends only when the client hangs up, so the socket stayed open.
  func close() {
    io?.close(flags: .stop)
    io = nil
  }
}
