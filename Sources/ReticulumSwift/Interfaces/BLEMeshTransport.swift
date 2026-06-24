import Foundation

/// Identifies a peer mesh device reachable over the BLE radio.
///
/// Concrete transports derive this from their underlying platform identifier
/// (e.g. `CBPeripheral.identifier.uuidString` when we are the central, or a
/// per-subscriber token when we are the peripheral). `BLEMeshInterface` only
/// ever treats this as an opaque routing key.
public typealias BLEMeshPeerID = String

/// Decouples BLE mesh radio I/O — advertising, scanning, GATT connection
/// management, and per-peer byte exchange — from the Reticulum-facing
/// interface logic in `BLEMeshInterface`.
///
/// ## Why this split exists
///
/// This mirrors the `RNodeTransport` paradigm already established in this
/// codebase for RNode-over-BLE (see `RNodeInterface.swift` /
/// `RNodeTransport`): CoreBluetooth specifics require live radio hardware,
/// runtime entitlements, and a run loop — none of which are exercisable in
/// `swift test`. So the platform-concrete adapter (e.g. a CoreBluetooth
/// implementation backed by `CBCentralManager`/`CBPeripheralManager`) is
/// supplied by the host application, exactly as `BLERNodeTransport` lives in
/// RetiOS rather than ReticulumSwift. `BLEMeshInterface` itself stays pure
/// Swift, talks only in peer IDs and raw bytes, and is fully unit-testable
/// against a mock conformance.
///
/// ## How this differs from `RNodeTransport`
///
/// `RNodeTransport` models a single point-to-point byte stream (phone ↔ one
/// RNode). A mesh is fundamentally multi-peer and symmetric: every device
/// must be discoverable by, and able to discover, every other device. So a
/// conforming transport is expected to run BOTH BLE roles concurrently:
///
///   - **Central**:    scan for nearby devices advertising the mesh service,
///                     connect to them, and exchange bytes over GATT
///                     characteristics (mirrors `BLERNodeTransport`'s NUS
///                     read/write conventions).
///   - **Peripheral**: advertise the mesh GATT service so nearby devices can
///                     discover and connect to *us* — without this, two
///                     phones running the app could never find each other,
///                     since CoreBluetooth centrals can only see peripherals.
public protocol BLEMeshTransport: AnyObject {
    /// Invoked when a peer becomes reachable for sending, in either BLE role.
    var peerConnected: ((BLEMeshPeerID) -> Void)? { get set }
    /// Invoked when a previously-reachable peer disconnects, drops out of
    /// range, or is otherwise lost.
    var peerDisconnected: ((BLEMeshPeerID) -> Void)? { get set }
    /// Invoked for every chunk of raw bytes received from a peer.
    ///
    /// Chunks may be fragments of a larger HDLC-framed message — BLE GATT
    /// payloads are bound by the negotiated link MTU (typically far smaller
    /// than a Reticulum packet), so `BLEMeshInterface` performs reassembly.
    /// The transport's only job is to ferry bytes in the order they arrived,
    /// per peer.
    var peerDataHandler: ((BLEMeshPeerID, Data) -> Void)? { get set }

    /// Peers currently reachable for sending.
    var connectedPeers: [BLEMeshPeerID] { get }

    /// Begin advertising the mesh GATT service (peripheral role) and
    /// scanning for other mesh devices (central role).
    func start() throws

    /// Stop all radio activity — advertising, scanning, and any open peer
    /// connections.
    func stop()

    /// Send raw bytes to one connected peer.
    ///
    /// The transport is responsible for chunking to the negotiated link MTU
    /// (mirroring `BLERNodeTransport.write`); `BLEMeshInterface` only ever
    /// hands over complete, already-framed messages.
    func send(_ data: Data, to peer: BLEMeshPeerID) throws
}
