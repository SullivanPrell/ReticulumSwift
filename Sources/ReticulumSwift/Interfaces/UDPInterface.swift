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
import Network

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
  /// Whether path requests received here are resolved recursively.
  public var recursivePrs: Bool = false
  /// Whether announces originating on this instance are sent on this interface.
  public var announcesFromInternal: Bool = true
  /// Mirrors Python's `Interface.announces_to_internal` (RNS 1.4.1).
  public var announcesToInternal: Bool? = nil
  /// Mirrors Python's `Interface.gravity` (RNS 1.4.1).
  public var gravity: Int = InterfaceMode.defaultGravity
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

  private var listener: NWListener?
  private var connection: NWConnection?
  private let queue: DispatchQueue
  /// Inbound connections accepted by the listener.
  ///
  /// Retained so stop() can
  /// cancel them (otherwise every inbound peer leaks its connection + receive
  /// loop) and pruned when their receive loop ends. Guarded by `connLock`
  /// (newConnectionHandler runs on `queue`, stop() on the caller thread).
  private var inboundConnections: [NWConnection] = []
  private let connLock = NSLock()

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

  /// The configured `listen_ip`.
  ///
  /// Python's `bind_ip`; reporting-only here, since
  /// `NWListener` binds every address.
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
    if let listenPort, let port = NWEndpoint.Port(rawValue: listenPort) {
      let listener = try NWListener(using: .udp, on: port)
      listener.newConnectionHandler = { [weak self] conn in
        guard let self else {
          conn.cancel()
          return
        }
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

  /// Takes the interface offline and releases its resources.
  public func stop() {
    listener?.cancel()
    listener = nil
    connection?.cancel()
    connection = nil
    connLock.lock()
    let inbound = inboundConnections
    inboundConnections.removeAll()
    connLock.unlock()
    for c in inbound { c.cancel() }
    isOnline = false
  }

  /// Transmits `packet` on the interface.
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
        // Receive loop ended—drop and cancel this inbound connection
        // so it doesn't accumulate.
        self.connLock.lock()
        self.inboundConnections.removeAll { $0 === conn }
        self.connLock.unlock()
        conn.cancel()
      }
    }
  }
}
