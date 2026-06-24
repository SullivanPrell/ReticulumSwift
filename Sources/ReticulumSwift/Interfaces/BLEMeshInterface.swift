import Foundation

/// BLE-radio mesh interface — lets the device's own Bluetooth Low Energy
/// radio mesh directly with nearby Reticulum nodes running this interface,
/// with no intermediate hardware (no RNode, no router, no access point).
///
/// ## Why this design
///
/// Neither the Python reference implementation nor ReticulumSwift has a
/// "phone meshes with phone over BLE" interface to mirror — Python RNS only
/// ever uses BLE as a *transport* to RNode LoRa hardware
/// (`RNS.Interfaces.RNodeInterface.BLEConnection`, built on the `bleak`
/// module), and ReticulumSwift already mirrors exactly that with
/// `RNodeTransport` / `BLERNodeTransport`. There is no "BLE mesh" paradigm
/// to follow in either codebase.
///
/// Lacking a BLE-mesh-specific precedent, this interface instead combines
/// the two closest established patterns already in this project:
///
/// 1. **Radio-I/O decoupling**, exactly like `RNodeInterface`/
///    `RNodeTransport`: every CoreBluetooth specific lives behind the
///    `BLEMeshTransport` protocol and is supplied by the host application
///    (see `BLEMeshTransport.swift` for the full rationale — in short,
///    `CBCentralManager`/`CBPeripheralManager` need live radio hardware and
///    runtime entitlements that `swift test` cannot provide). This keeps
///    `BLEMeshInterface` pure Swift, deterministic, and unit-testable
///    against a mock transport.
/// 2. **Peer-table fan-out**, exactly like `AutoInterface` — the closest
///    functional analog to a BLE mesh: a set of nearby devices that
///    discover each other and exchange raw packet bytes over a
///    broadcast-ish shared medium. This interface tracks connected peers
///    and fans every outbound packet out to all of them; Reticulum's own
///    duplicate suppression and routing logic (in `Transport`) handles the
///    resulting mesh-flood semantics, so the interface itself stays a dumb
///    shared medium — conceptually no different from a LAN segment or a
///    LoRa channel.
///
/// ## Framing
///
/// BLE GATT payloads are bound by the negotiated link MTU (commonly in the
/// 20–512 byte range) — far smaller than a Reticulum packet can be. So,
/// exactly like `TCPClientInterface` / `BackboneInterface` / `RNodeInterface`,
/// outbound packets are delimited with `HDLC` framing before transmission,
/// and every peer gets its own `HDLC.FrameDecoder` to reassemble fragments
/// back into complete frames as bytes trickle in over its link. Per-peer
/// decoders are essential — bytes from different peers must never be mixed,
/// or a partial frame from one peer would corrupt another's stream.
///
/// Because this is a wholly new interface type with no Python counterpart,
/// there is no cross-implementation wire format to match here — only Swift
/// nodes (iOS/macOS) can use it, and any two such nodes already agree, since
/// they share the same `HDLC` + `Packet` wire format.
public final class BLEMeshInterface: Interface {

    // MARK: - Tunable defaults

    /// Conservative throughput estimate for a BLE 5 GATT link carrying
    /// HDLC-framed Reticulum packets. Mirrors the `bitrateGuess` convention
    /// used by `I2PInterface`/`AX25KISSInterface` — a configurable estimate
    /// for link-quality heuristics, not a measured value.
    public static let bitrateGuess: Int = 1_000_000

    /// Default IFAC size in bytes for this interface type, mirroring the
    /// `DEFAULT_IFAC_SIZE` convention every custom interface must declare
    /// per `ExampleInterface.py`.
    public static let defaultIfacSize: Int = 8

    // MARK: - Interface conformance

    public let name: String
    public private(set) var bitrate: Int
    public private(set) var isOnline: Bool = false

    /// A Reticulum packet must fit inside one reassembled HDLC frame, and
    /// BLE links cannot negotiate arbitrarily large MTUs — so, like
    /// `AutoInterface`, this interface declares a fixed hardware MTU at the
    /// standard Reticulum packet ceiling rather than auto-negotiating.
    public let hwMtu: Int? = Constants.mtu
    public let fixedMtu: Bool = true

    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?

    public private(set) var rxBytes: Int = 0
    public private(set) var txBytes: Int = 0
    public private(set) var rxPackets: Int = 0
    public private(set) var txPackets: Int = 0

    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = BLEMeshInterface.defaultIfacSize

    /// Type-qualified display name, matching the `"<Type>[<name>]"`
    /// convention other interfaces use in `rnstatus`-style output
    /// (e.g. `AutoInterface[local]`).
    public var displayName: String { "BLEMeshInterface[\(name)]" }

    // MARK: - State

    private let transport: BLEMeshTransport

    /// Per-peer reassembly state.
    private struct PeerState {
        let decoder = HDLC.FrameDecoder()
        var lastHeard = Date()
    }
    private var peers: [BLEMeshPeerID: PeerState] = [:]
    private let peersLock = NSLock()

    /// Snapshot of currently-meshed peer IDs. Safe to read from any thread —
    /// intended for UI display (peer list, mesh size indicator, etc.).
    public var connectedPeerIDs: [BLEMeshPeerID] {
        peersLock.lock(); defer { peersLock.unlock() }
        return Array(peers.keys)
    }

    /// Number of peers currently meshed with us.
    public var peerCount: Int {
        peersLock.lock(); defer { peersLock.unlock() }
        return peers.count
    }

    // MARK: - Init

    /// - Parameters:
    ///   - name: Interface name, as configured by the user.
    ///   - transport: Platform-concrete BLE radio adapter (e.g. a
    ///     CoreBluetooth implementation supplied by the host app — see
    ///     `BLEMeshTransport` for why this is injected rather than owned).
    ///   - bitrate: Optional override of `bitrateGuess`.
    public init(name: String, transport: BLEMeshTransport, bitrate: Int = BLEMeshInterface.bitrateGuess) {
        self.name = name
        self.transport = transport
        self.bitrate = bitrate
    }

    // MARK: - Lifecycle

    public func start() throws {
        transport.peerConnected = { [weak self] peer in self?.handlePeerConnected(peer) }
        transport.peerDisconnected = { [weak self] peer in self?.handlePeerDisconnected(peer) }
        transport.peerDataHandler = { [weak self] peer, data in self?.handlePeerData(peer, data) }
        try transport.start()
        isOnline = true
    }

    public func stop() {
        isOnline = false
        transport.stop()
        peersLock.lock()
        peers.removeAll()
        peersLock.unlock()
    }

    // MARK: - Outbound

    /// IFAC-wraps and HDLC-frames the packet (mirrors
    /// `TCPClientInterface.send`'s `HDLC.frame(wrapIfac(raw))`), then
    /// broadcasts the framed bytes to every currently-meshed peer.
    ///
    /// The interface does not attempt to be "smart" about routing — like
    /// `AutoInterface` fanning out to every known peer on the LAN, this
    /// floods the frame to the whole local mesh neighbourhood and lets
    /// `Transport`'s duplicate-suppression and path logic sort out the
    /// rest. That is the same flood-and-suppress model the wider Reticulum
    /// network already relies on for shared-medium interfaces.
    public func send(_ packet: Packet) throws {
        guard isOnline else { return }
        let raw = try packet.pack()
        let framed = HDLC.frame(wrapIfac(raw))
        txBytes += raw.count    // Python convention: count unframed payload bytes
        txPackets += 1

        peersLock.lock()
        let targets = Array(peers.keys)
        peersLock.unlock()

        for peer in targets {
            try? transport.send(framed, to: peer)
        }
    }

    // MARK: - Peer lifecycle

    private func handlePeerConnected(_ peer: BLEMeshPeerID) {
        peersLock.lock()
        peers[peer] = PeerState()
        peersLock.unlock()
    }

    private func handlePeerDisconnected(_ peer: BLEMeshPeerID) {
        peersLock.lock()
        peers.removeValue(forKey: peer)
        peersLock.unlock()
    }

    // MARK: - Inbound

    /// Feeds raw bytes from one peer's link into that peer's frame decoder
    /// and delivers every completed frame upward — mirrors
    /// `TCPClientInterface.beginReceiveLoop`'s `decoder.feed` → dispatch.
    private func handlePeerData(_ peer: BLEMeshPeerID, _ data: Data) {
        peersLock.lock()
        // Tolerate bytes arriving before/racing the connection callback —
        // create peer state on first sight rather than dropping data.
        if peers[peer] == nil { peers[peer] = PeerState() }
        peers[peer]?.lastHeard = Date()
        let frames = peers[peer]?.decoder.feed(data) ?? []
        peersLock.unlock()

        for frame in frames {
            rxBytes += frame.count   // Python convention: count unframed payload bytes
            rxPackets += 1
            if let handler = rawInboundHandler {
                handler(frame, self)
            } else if let packet = try? Packet.unpack(frame) {
                inboundHandler?(packet, self)
            }
        }
    }
}
