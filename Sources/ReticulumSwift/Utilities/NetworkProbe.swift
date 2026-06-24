import Foundation

/// Network probe utility — sends a small packet to a destination and tracks the receipt.
///
/// Mirrors the core logic of `RNS/Utilities/rnprobe.py`.
/// The CLI-specific output (progress spinners, exit codes) is not included; callers
/// can layer that on top by inspecting the returned `PacketReceipt`.
///
/// ### Usage
/// ```swift
/// let probe = NetworkProbe(transport: transport)
/// let receipt = probe.send(to: destinationHash, size: 32)
/// // receipt.status == .delivered → round-trip succeeded
/// ```
public final class NetworkProbe {

    // MARK: - Class constants

    /// Default probe payload size in bytes.
    /// Python: `DEFAULT_PROBE_SIZE = 16`.
    public static let defaultProbeSize: Int = 16

    /// Default reply timeout in seconds.
    /// Python: `DEFAULT_TIMEOUT = 12`.
    public static let defaultTimeout: TimeInterval = 12

    /// Application name (the utility has no `APP_NAME`, but is identified as "rnprobe").
    public static let appName: String = "rnprobe"

    // MARK: - Instance state

    /// Number of random bytes sent as probe payload.
    public private(set) var size: Int

    /// Seconds to wait for a delivery receipt before declaring a timeout.
    public private(set) var timeout: TimeInterval

    private weak var transport: Transport?

    // MARK: - Initialisation

    /// Create a probe helper attached to `transport`.
    ///
    /// - Parameters:
    ///   - transport: The `Transport` instance used to send packets.
    ///   - defaultSize: Payload size (bytes). Defaults to `NetworkProbe.defaultProbeSize`.
    ///   - timeout: Reply timeout (seconds). Defaults to `NetworkProbe.defaultTimeout`.
    public init(transport: Transport,
                defaultSize: Int = NetworkProbe.defaultProbeSize,
                timeout: TimeInterval = NetworkProbe.defaultTimeout) {
        self.transport = transport
        self.size      = defaultSize
        self.timeout   = timeout
    }

    // MARK: - Probe

    /// Send a single probe packet to `destination` and return the `PacketReceipt`.
    ///
    /// The receipt's `status` field will eventually become `.delivered` or `.failed`.
    /// Call this from a background thread if you want to block-wait on delivery.
    ///
    /// Mirrors `rnprobe.py::program_setup` — the actual packet send + receipt loop.
    ///
    /// - Parameters:
    ///   - destination: An outbound `Destination` of type `.single`.
    ///   - size: Payload size override. `nil` uses `self.size`.
    /// - Returns: The `PacketReceipt` for delivery tracking, or `nil` if the packet
    ///            could not be packed (e.g. exceeds MTU).
    @discardableResult
    public func send(to destination: Destination,
                     size: Int? = nil) -> PacketReceipt? {
        guard let transport else { return nil }
        let payloadSize = size ?? self.size
        let payload = Data((0..<payloadSize).map { _ in UInt8.random(in: 0...255) })
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: destination.hash,
            data: payload
        )
        // Verify the packed size would fit in the MTU before sending.
        guard packet.rawByteCount <= Reticulum.mtu else { return nil }
        return try? transport.send(packet)
    }
}
