import Foundation

// MARK: - I2PInterface

/// Reticulum interface that routes traffic over the I2P anonymous network.
/// Python: `I2PInterface` (RNS/Interfaces/I2PInterface.py)
///
/// Each configured peer (a `.b32.i2p` address or full base64 destination)
/// becomes a separate `I2PInterfacePeer` that dials out through the daemon's
/// SAM bridge and registers with Transport as its own routing endpoint —
/// the parent interface itself never transmits (Python: `process_outgoing:
/// pass`). Packets are HDLC-framed (same as BackboneInterface/TCPInterface).
public final class I2PInterface: Interface {

    // MARK: - Python class constants

    /// Python: `BITRATE_GUESS = 256*1000` (bits/s)
    public static let bitrateGuess:    Int = 256_000
    /// Python: `DEFAULT_IFAC_SIZE = 16`
    public static let defaultIfacSize: Int = 16
    /// Python: `self.HW_MTU = 1064`
    public static let hwMtu:           Int = 1064

    // MARK: - Interface protocol properties

    public let  name:    String
    public var  bitrate: Int  = I2PInterface.bitrateGuess
    public var  isOnline: Bool = false

    // Traffic counters
    public private(set) var rxBytes:   Int = 0
    public private(set) var txBytes:   Int = 0
    public private(set) var rxPackets: Int = 0
    public private(set) var txPackets: Int = 0

    // Hardware MTU
    public var hwMtu: Int? { I2PInterface.hwMtu }

    // Mode
    public var mode: InterfaceMode = .full
    public var recursivePrs: Bool = false
    public var announcesFromInternal: Bool = true

    // Tunnel
    public var wantsTunnel: Bool   = false
    public var tunnelID:    Data?  = nil

    // IFAC (inherited by spawned peers)
    public var ifacIdentity: Identity? = nil
    public var ifacKey:      Data?     = nil
    public var ifacSize:     Int       = I2PInterface.defaultIfacSize

    // Inbound handlers set by Transport
    public var inboundHandler:    ((Packet, any Interface) -> Void)? = nil
    public var rawInboundHandler: ((Data, any Interface) -> Void)?   = nil

    /// The parent interface never routes packets itself — its dialed peers
    /// are the routing endpoints (mirrors Python, where the parent's
    /// `process_outgoing` is a no-op and `OUT = False`).
    public var isRoutingEndpoint: Bool { false }

    // MARK: - I2P-specific properties

    /// Whether this interface accepts incoming I2P connections.
    /// Python: `connectable`
    public var connectable:       Bool = false
    /// Python: `self.i2p_tunneled = True`
    public var i2pTunneled:       Bool = true
    /// Python: `self.supports_discovery = True`
    public var supportsDiscovery: Bool = true
    /// Base-32 address for this I2P tunnel, if established. Python: `self.b32`
    public var b32:               String? = nil
    /// Human-readable tunnel state description. Python: `tunnelstate`
    public var tunnelState:       String? = nil

    /// Remote destinations to dial (`.b32.i2p` or base64). Python: `peers`.
    public let peers: [String]

    /// Overrides the SAM socket factory on every spawned peer (tests).
    public var samSocketFactory: (() -> SAMSocket)?

    /// Called when a dialed peer comes online. Transport wires this to
    /// `register(interface:)` — mirroring `TCPServerInterface.onClientConnected`.
    public var onPeerConnected:    ((any Interface) -> Void)?
    /// Called when a dialed peer drops offline; Transport deregisters it.
    public var onPeerDisconnected: ((any Interface) -> Void)?

    /// Outbound peers spawned from `peers` (Python keeps these in Transport
    /// only; kept here so stop()/restart and the UI can reach them).
    public private(set) var peerInterfaces: [I2PInterfacePeer] = []

    /// Python: `len(spawned_interfaces)` (inbound connections only)
    public var clients: Int {
        lock.lock(); defer { lock.unlock() }
        return spawned.count
    }

    // MARK: - Private

    private var spawned: [I2PInterfacePeer] = []
    private let lock    = NSLock()
    private let daemon:  I2PDaemonProtocol
    private let dataDir: URL

    // MARK: - Init

    /// - Parameters:
    ///   - name:          Interface name (e.g. `"I2P"`)
    ///   - daemon:        Daemon providing the SAM bridge (embedded or external).
    ///   - dataDirectory: Directory for i2pd router data.
    ///   - connectable:   Whether to accept incoming I2P connections.
    ///   - peers:         Remote I2P destinations to dial (b32 or base64).
    public init(name: String,
                daemon: I2PDaemonProtocol,
                dataDirectory: URL,
                connectable: Bool = false,
                peers: [String] = []) {
        self.name        = name
        self.daemon      = daemon
        self.dataDir     = dataDirectory
        self.connectable = connectable
        self.peers       = peers
    }

    // MARK: - Interface lifecycle

    /// Start the embedded i2pd daemon and dial all configured peers.
    /// Python: `I2PInterface.__init__` peer loop —
    /// `interface_name = self.name + " to " + peer_addr`.
    public func start() throws {
        try daemon.start(dataDirectory: dataDir)
        isOnline = true

        var spawnedPeers: [I2PInterfacePeer] = []
        for peerAddr in peers {
            let peer = I2PInterfacePeer(name: "\(name) to \(peerAddr)",
                                        targetI2PDestination: peerAddr,
                                        parentInterface: self)
            peer.samPort       = daemon.samPort
            peer.socketFactory = samSocketFactory
            peer.ifacIdentity  = ifacIdentity
            peer.ifacKey       = ifacKey
            peer.ifacSize      = ifacSize
            peer.onConnected    = { [weak self] p in self?.onPeerConnected?(p) }
            peer.onDisconnected = { [weak self] p in self?.onPeerDisconnected?(p) }
            spawnedPeers.append(peer)
        }
        lock.lock(); peerInterfaces = spawnedPeers; lock.unlock()
        for peer in spawnedPeers { try? peer.start() }
    }

    /// Stop all peers and the embedded daemon. `start()` respawns peers
    /// from the stored config.
    public func stop() {
        isOnline = false
        lock.lock()
        let outbound = peerInterfaces
        let inbound  = spawned
        peerInterfaces = []
        spawned = []
        lock.unlock()
        for peer in outbound { peer.stop() }
        for peer in inbound  { peer.stop() }
        daemon.stop()
    }

    // MARK: - Packet send

    /// The parent is not a routing endpoint; Transport routes through the
    /// individual peers. Kept as a broadcast for API compatibility.
    public func send(_ packet: Packet) throws {
        lock.lock(); let all = peerInterfaces + spawned; lock.unlock()
        for peer in all where peer.online { try? peer.send(packet) }
    }

    // MARK: - Spawned interface management (inbound peer registry)

    public func addSpawnedInterface(_ peer: I2PInterfacePeer) {
        lock.lock(); spawned.append(peer); lock.unlock()
    }

    public func removeSpawnedInterface(_ peer: I2PInterfacePeer) {
        lock.lock(); spawned.removeAll { $0 === peer }; lock.unlock()
    }
}
