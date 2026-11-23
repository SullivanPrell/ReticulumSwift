//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

/// Bidirectional UDP transport for Reticulum packets, wire-compatible
/// with `RNS.Interfaces.UDPInterface`.
///
/// One datagram carries exactly one
/// raw `Packet`—no HDLC framing.
///
/// Provide a `listenPort` to receive datagrams, and a
/// `forwardHost`/`forwardPort` to address outbound traffic. Either
/// direction is optional, but at least one must be configured.
public final class UDPInterface: Interface {
  /// Per-interface mutable configuration (mode, announce rate control, ingress/egress
  /// control, the `ic_*` tunables).
  ///
  /// One stored property satisfies the whole settable set;
  /// see `InterfaceState` and `swift_devel/bugs/025-*.md`.
  public let interfaceState = InterfaceState()
  /// Interface name as it appears in configuration and status output.
  public let name: String
  /// UDP port bound for inbound traffic, or `nil` when the interface only sends.
  public let listenPort: UInt16?
  /// Host outbound packets are sent to, or `nil` when the interface only listens.
  public let forwardHost: String?
  /// UDP port outbound packets are sent to, or `nil` when the interface only listens.
  public let forwardPort: UInt16?
  /// Nominal interface bitrate in bits per second.
  public var bitrate: Int = 10_000_000
  private let onlineFlag = LockedFlag(false)
  /// Whether the interface is up and able to carry traffic.
  public private(set) var isOnline: Bool {
    get { onlineFlag.value }
    set { onlineFlag.value = newValue }
  }

  // Python UDPInterface: HW_MTU = 1064
  /// Hardware maximum transmission unit in bytes, or `nil` when unconstrained.
  public let hwMtu: Int? = 1_064

  /// Called with each packet decoded from an inbound frame.
  public var inboundHandler: ((Packet, any Interface) -> Void)?
  /// Called with each inbound frame, before packet decoding.
  public var rawInboundHandler: ((Data, any Interface) -> Void)?
  /// Identity authenticating this interface under IFAC, or `nil` when IFAC is off.
  public var ifacIdentity: Identity?
  /// Derived IFAC key used to sign and verify frames.
  public var ifacKey: Data?
  /// IFAC authentication field size in bytes.
  public var ifacSize: Int = Constants.defaultIfacSize

  /// Lock-guarded—written from this interface's I/O queue while the UI
  /// and status reporting read from another thread.
  ///
  /// See `InterfaceCounters`.
  private let counters = InterfaceCounters()
  /// Total bytes received on this interface.
  public var rxBytes: Int { counters.rxBytes }
  /// Total bytes transmitted on this interface.
  public var txBytes: Int { counters.txBytes }

  /// The one IPv4 socket that receives and sends.
  ///
  /// It stands in for Python's `UDPServer` plus its per-send `SO_BROADCAST` socket
  /// (`UDPInterface.py:101-103`, `:118-122`) and binds `listenPort` when there is one.
  /// Network.framework can't send a broadcast and gives each source its own connection, which
  /// is why this is BSD.
  private var socketFD: Int32 = -1
  private var readSource: DispatchSourceRead?
  private let queue: DispatchQueue
  /// Touched only on `queue`.
  private var receiveBuffer = [UInt8](repeating: 0, count: 65_535)

  /// Python `UDPInterface.__str__` (`UDPInterface.py:131-132`):
  /// `"UDPInterface["+self.name+"/"+self.bind_ip+":"+str(self.bind_port)+"]"`, where
  /// `bind_ip` is the configured `listen_ip` (`UDPInterface.py:63`, `:91`).
  ///
  /// Hardcoding
  /// `0.0.0.0` here made a loopback-bound Swift interface report a different name—and
  /// so a different `Interface.hash`—than the Python interface beside it.
  public var displayName: String {
    let ip = bindIP.contains(":") ? "[\(bindIP)]" : bindIP
    let port = listenPort ?? forwardPort ?? 0
    return "UDPInterface[\(name)/\(ip):\(port)]"
  }

  /// The address the listener binds, the configured `listen_ip`.
  ///
  /// Python's `bind_ip` (`UDPInterface.py:92`, `:101-103`). The default, `0.0.0.0`, binds
  /// every address.
  public let bindIP: String

  /// Creates a UDP interface that listens, forwards, or both.
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

  /// Brings the interface online.
  public func start() throws {
    let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard s >= 0 else { throw UDPInterfaceError.socket(errno) }
    var on: Int32 = 1
    let size = socklen_t(MemoryLayout<Int32>.size)
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, size)
    setsockopt(s, SOL_SOCKET, SO_BROADCAST, &on, size)

    if let listenPort {
      guard var address = Self.ipv4Address(bindIP, port: listenPort) else {
        close(s)
        throw UDPInterfaceError.unresolvable(bindIP)
      }
      let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
      guard bound == 0 else {
        let code = errno
        close(s)
        throw UDPInterfaceError.socket(code)
      }
      let source = DispatchSource.makeReadSource(fileDescriptor: s, queue: queue)
      source.setEventHandler { [weak self] in self?.receive(on: s) }
      // The source owns a listening socket: closing it here can't race a read.
      source.setCancelHandler { close(s) }
      source.resume()
      readSource = source
    }
    socketFD = s
    isOnline = true
  }

  /// Takes the interface offline and releases its resources.
  public func stop() {
    isOnline = false
    if let readSource {
      readSource.cancel()
    } else if socketFD >= 0 {
      close(socketFD)
    }
    readSource = nil
    socketFD = -1
  }

  /// Transmits `packet` on the interface.
  public func send(_ packet: Packet) throws {
    guard socketFD >= 0, let forwardHost, let forwardPort,
      var destination = Self.ipv4Address(forwardHost, port: forwardPort)
    else { return }
    let raw = try packet.pack()
    let sent = wrapIfac(raw).withUnsafeBytes { bytes in
      withUnsafePointer(to: &destination) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          sendto(
            socketFD, bytes.baseAddress, bytes.count, 0, $0,
            socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
    }
    // Python counts only what it transmitted (`UDPInterface.py:123`).
    if sent >= 0 { counters.addTx(bytes: raw.count) }
  }

  private func receive(on s: Int32) {
    let n = recv(s, &receiveBuffer, receiveBuffer.count, 0)
    guard n > 0 else { return }
    let data = Data(receiveBuffer[0..<n])
    counters.addRx(bytes: data.count)
    if let h = rawInboundHandler {
      h(data, self)
    } else if let packet = try? Packet.unpack(data) {
      inboundHandler?(packet, self)
    }
  }

  /// `host` (a dotted quad or a name, as Python's `sendto` takes) and `port` as an IPv4
  /// socket address.
  private static func ipv4Address(_ host: String, port: UInt16) -> sockaddr_in? {
    var hints = addrinfo()
    hints.ai_family = AF_INET
    hints.ai_socktype = SOCK_DGRAM
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
    defer { freeaddrinfo(first) }
    var address = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
      $0.pointee
    }
    address.sin_port = port.bigEndian
    return address
  }
}

/// Errors raised while bringing a UDP interface up.
public enum UDPInterfaceError: Error {
  /// A socket call failed with this `errno`.
  case socket(Int32)
  /// The listen address didn't resolve to IPv4.
  case unresolvable(String)
}

extension UDPInterface {
  /// `UDPInterface.py:81`.
  public var sharedMedium: Bool { true }
}
