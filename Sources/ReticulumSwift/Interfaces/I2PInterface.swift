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

// MARK: - I2PInterface

/// Reticulum interface that routes traffic over the I2P anonymous network.
/// Python: `I2PInterface` (RNS/Interfaces/I2PInterface.py)
///
/// Each configured peer (a `.b32.i2p` address or full base64 destination)
/// becomes a separate `I2PInterfacePeer` that dials out through the daemon's
/// SAM bridge and registers with Transport as its own routing endpoint—the
/// parent interface itself never transmits (Python: `process_outgoing:
/// pass`). Packets are HDLC-framed (same as BackboneInterface/TCPInterface).
public final class I2PInterface: Interface {
  /// Per-interface mutable configuration (mode, announce rate control, ingress/egress
  /// control, the `ic_*` tunables).
  ///
  /// One stored property satisfies the whole settable set;
  /// see `InterfaceState` and `swift_devel/bugs/025-*.md`.
  public let interfaceState = InterfaceState()

  // MARK: - Python class constants

  /// Assumed bitrate for an I2P tunnel, in bits per second.
  ///
  /// Python: `BITRATE_GUESS = 256*1000` (bits/s)
  public static let bitrateGuess: Int = 256_000
  /// Default IFAC authentication field size in bytes.
  ///
  /// Python: `DEFAULT_IFAC_SIZE = 16`
  public static let defaultIfacSize: Int = 16
  /// Hardware maximum transmission unit in bytes.
  ///
  /// Python: `self.HW_MTU = 1064`
  public static let hwMtu: Int = 1064

  // MARK: - Interface protocol properties

  /// Interface name as it appears in configuration and status output.
  public let name: String
  /// Nominal interface bitrate in bits per second.
  public var bitrate: Int = I2PInterface.bitrateGuess
  /// Whether the interface is up and able to carry traffic.
  public var isOnline: Bool = false

  // MARK: - Traffic counters
  //
  // The parent interface performs no I/O of its own—every byte moves
  // through a dialed (`peerInterfaces`) or accepted (`spawned`) peer, and
  // each peer keeps its own lock-guarded counters. These were previously
  // plain stored properties that nothing ever incremented, so the I2P row
  // reported 0 B in both directions no matter how much traffic the peers
  // carried. Summing the peers is what the numbers were always meant to be.

  private var allPeers: [I2PInterfacePeer] {
    lock.lock()
    defer { lock.unlock() }
    return peerInterfaces + spawned
  }

  /// Total bytes received across every peer.
  public var rxBytes: Int { allPeers.reduce(0) { $0 + $1.rxBytes } }
  /// Total bytes transmitted across every peer.
  public var txBytes: Int { allPeers.reduce(0) { $0 + $1.txBytes } }
  /// Total packets received across every peer.
  public var rxPackets: Int { allPeers.reduce(0) { $0 + $1.rxPackets } }
  /// Total packets transmitted across every peer.
  public var txPackets: Int { allPeers.reduce(0) { $0 + $1.txPackets } }

  // Hardware MTU
  /// Hardware maximum transmission unit in bytes, or `nil` when unconstrained.
  public var hwMtu: Int? { I2PInterface.hwMtu }

  // Mode is held in `interfaceState` like every other interface. This type used to be the only
  // one with a settable `mode`, which is what made `bugs/025` look like a config-parser gap
  // rather than a protocol-shape gap.
  /// Whether path requests received here are resolved recursively.
  public var recursivePrs: Bool = false
  /// Whether announces originating on this instance are sent on this interface.
  public var announcesFromInternal: Bool = true
  /// Mirrors Python's `Interface.announces_to_internal` (RNS 1.4.1).
  public var announcesToInternal: Bool? = nil
  /// Mirrors Python's `Interface.gravity` (RNS 1.4.1).
  public var gravity: Int = InterfaceMode.defaultGravity

  // Tunnel
  /// Whether the interface asks Transport to establish a tunnel over it.
  public var wantsTunnel: Bool = false
  /// Identifier of the transport tunnel established over this interface.
  public var tunnelID: Data? = nil

  // IFAC (inherited by spawned peers)
  /// Identity authenticating this interface under IFAC, or `nil` when IFAC is off.
  public var ifacIdentity: Identity? = nil
  /// Derived IFAC key used to sign and verify frames.
  public var ifacKey: Data? = nil
  /// IFAC authentication field size in bytes.
  public var ifacSize: Int = I2PInterface.defaultIfacSize

  // Inbound handlers set by Transport
  /// Called with each packet decoded from an inbound frame.
  public var inboundHandler: ((Packet, any Interface) -> Void)? = nil
  /// Called with each inbound frame, before packet decoding.
  public var rawInboundHandler: ((Data, any Interface) -> Void)? = nil

  /// The parent interface never routes packets itself—its dialed peers
  /// are the routing endpoints (mirrors Python, where the parent's
  /// `process_outgoing` is a no-op and `OUT = False`).
  public var isRoutingEndpoint: Bool { false }

  // MARK: - I2P-specific properties

  /// Whether this interface accepts incoming I2P connections.
  /// Python: `connectable`
  public var connectable: Bool = false
  /// Whether traffic is carried inside an I2P tunnel.
  ///
  /// Python: `self.i2p_tunneled = True`
  public var i2pTunneled: Bool = true
  /// Whether the interface takes part in peer discovery.
  ///
  /// Python: `self.supports_discovery = True`
  public var supportsDiscovery: Bool = true

  /// Python publishes the tunnel's `b32` as `REACHABLE_ON`, but only once the tunnel
  /// accepts incoming connections (`Discovery.py:185-186`).
  public var discoveryEndpointAddress: String? { connectable ? b32 : nil }
  /// Base-32 address for this I2P tunnel, if established. Python: `self.b32`
  public var b32: String? = nil
  /// Human-readable tunnel state description. Python: `tunnelstate`
  public var tunnelState: String? = nil

  /// Remote destinations to dial (`.b32.i2p` or base64).
  ///
  /// Python: `peers`.
  public let peers: [String]

  /// Overrides the SAM socket factory on every spawned peer (tests).
  public var samSocketFactory: (() -> SAMSocket)?

  /// Called when a dialed peer comes online.
  ///
  /// Transport wires this to
  /// `register(interface:)`—mirroring `TCPServerInterface.onClientConnected`.
  public var onPeerConnected: ((any Interface) -> Void)?
  /// Called when a dialed peer drops offline; Transport deregisters it.
  public var onPeerDisconnected: ((any Interface) -> Void)?

  /// Outbound peers spawned from `peers` (Python keeps these in Transport
  /// only; kept here so stop()/restart and the UI can reach them).
  public private(set) var peerInterfaces: [I2PInterfacePeer] = []

  /// Number of inbound peer connections currently served.
  ///
  /// Python: `len(spawned_interfaces)` (inbound connections only)
  public var clients: Int {
    lock.lock()
    defer { lock.unlock() }
    return spawned.count
  }

  // MARK: - Private

  private var spawned: [I2PInterfacePeer] = []
  private let lock = NSLock()
  private let daemon: I2PDaemonProtocol
  private let dataDir: URL

  // MARK: - Init

  /// - Parameters:
  ///   - name:          Interface name (for example, `"I2P"`)
  ///   - daemon:        Daemon providing the SAM bridge (embedded or external).
  ///   - dataDirectory: Directory for i2pd router data.
  ///   - connectable:   Whether to accept incoming I2P connections.
  ///   - peers:         Remote I2P destinations to dial (b32 or base64).
  public init(
    name: String,
    daemon: I2PDaemonProtocol,
    dataDirectory: URL,
    connectable: Bool = false,
    peers: [String] = []
  ) {
    self.name = name
    self.daemon = daemon
    self.dataDir = dataDirectory
    self.connectable = connectable
    self.peers = peers
  }

  // MARK: - Interface lifecycle

  /// Start the embedded i2pd daemon and dial all configured peers.
  ///
  /// Python: `I2PInterface.__init__` peer loop—`interface_name
  /// = self.name + " to " + peer_addr`.
  public func start() throws {
    try daemon.start(dataDirectory: dataDir)
    isOnline = true

    var spawnedPeers: [I2PInterfacePeer] = []
    for peerAddr in peers {
      let peer = I2PInterfacePeer(
        name: "\(name) to \(peerAddr)",
        targetI2PDestination: peerAddr,
        parentInterface: self)
      peer.samPort = daemon.samPort
      peer.socketFactory = samSocketFactory
      peer.ifacIdentity = ifacIdentity
      peer.ifacKey = ifacKey
      peer.ifacSize = ifacSize
      // Spawned peers are the real routing endpoints, so the parent's
      // routing preference has to reach them. Mirrors Python's
      // `spawned_interface.gravity = self.gravity` (RNS 1.4.1, 3ca71527).
      peer.gravity = gravity
      peer.onConnected = { [weak self] p in self?.onPeerConnected?(p) }
      peer.onDisconnected = { [weak self] p in self?.onPeerDisconnected?(p) }
      spawnedPeers.append(peer)
    }
    lock.lock()
    peerInterfaces = spawnedPeers
    lock.unlock()
    for peer in spawnedPeers { try? peer.start() }
  }

  /// Stop all peers and the embedded daemon. `start()` respawns peers
  /// from the stored config.
  public func stop() {
    isOnline = false
    lock.lock()
    let outbound = peerInterfaces
    let inbound = spawned
    peerInterfaces = []
    spawned = []
    lock.unlock()
    for peer in outbound { peer.stop() }
    for peer in inbound { peer.stop() }
    daemon.stop()
  }

  // MARK: - Packet send

  /// The parent isn't a routing endpoint; Transport routes through the
  /// individual peers.
  ///
  /// Kept as a broadcast for API compatibility.
  public func send(_ packet: Packet) throws {
    lock.lock()
    let all = peerInterfaces + spawned
    lock.unlock()
    for peer in all where peer.online { try? peer.send(packet) }
  }

  // MARK: - Spawned interface management (inbound peer registry)

  /// Registers a peer interface spawned by an inbound connection.
  public func addSpawnedInterface(_ peer: I2PInterfacePeer) {
    // Inbound (accepted) peers inherit routing preference from the parent
    // just like the outbound ones spawned in `start()`.
    //
    // Nothing in the library calls this yet—the SAM `STREAM ACCEPT`
    // inbound-listen path isn't implemented, so today only tests reach it.
    // The assignment belongs here rather than at the future call site: it's
    // the parent that knows its own gravity, and an inbound peer that routes
    // without it would quietly ignore the operator's path preference.
    peer.gravity = gravity
    lock.lock()
    spawned.append(peer)
    lock.unlock()
  }

  /// Removes a spawned peer interface.
  public func removeSpawnedInterface(_ peer: I2PInterfacePeer) {
    lock.lock()
    spawned.removeAll { $0 === peer }
    lock.unlock()
  }
}
