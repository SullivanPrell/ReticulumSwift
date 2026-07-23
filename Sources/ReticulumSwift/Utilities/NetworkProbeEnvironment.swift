import Foundation
import Security

// Live conformers of the ``NetworkProbe`` seams. Kept apart from `NetworkProbe.swift` so
// the pure logic file stays free of Transport / RPC coupling and remains trivially
// testable. Everything here is platform-neutral: Foundation, Security and BSD sockets are
// available on iOS, tvOS and watchOS as well as macOS.

// MARK: - Receipt

/// Python: `RNS.PacketReceipt` as `rnprobe` reads it (rnprobe.py:136-186).
extension PacketReceipt: ProbeReceipt {

    /// Python: `receipt.proof_packet != None` (rnprobe.py:181).
    public var hasProofPacket: Bool { proofPacket != nil }

    /// Python: `receipt.proof_packet.rssi` (rnprobe.py:182). Python's value is an int off
    /// the receiving RNode interface; Swift stores a `Float` in the same slot.
    public var proofRssi: Float? { proofPacket?.rssi }

    /// Python: `receipt.proof_packet.snr` (rnprobe.py:185).
    public var proofSnr: Float? { proofPacket?.snr }

    /// Python: `receipt.proof_packet.packet_hash` — the FULL 32-byte SHA-256
    /// (Packet.py:342-344), which is what rnprobe passes to `get_packet_rssi` and friends.
    public var proofPacketFullHash: Data? {
        guard let proofPacket else { return nil }
        return try? proofPacket.packetHash()
    }

    /// The 16-byte form of the same hash — the key a Swift daemon's PHY caches use.
    public var proofPacketTruncatedHash: Data? {
        guard let proofPacket else { return nil }
        return try? proofPacket.truncatedPacketHash()
    }
}

// MARK: - Network

/// Live ``ProbeNetwork`` over a running `Transport`, optionally augmented by an
/// ``RPCClient`` when this process is attached to a shared instance.
///
/// This deliberately does **not** delegate to `Reticulum.getNextHop`,
/// `getNextHopIfName`, `getFirstHopTimeout`, `getPacketRssi`, `getPacketSnr` or
/// `getPacketQ`. Those look exactly like their Python namesakes but are pure `transport.*`
/// pass-throughs with no shared-instance branch, whereas every Python original switches to
/// RPC when `is_connected_to_shared_instance` (Reticulum.py:1547-1638). Routing through
/// them would silently disable the whole RPC half of the probe's reporting.
public final class TransportProbeNetwork: ProbeNetwork {

    private let transport: Transport
    private let rpc: RPCClient?

    /// - Parameters:
    ///   - transport: the local stack. Even as a local client this owns a real path table,
    ///     populated from the shared instance over the `LocalInterface`, so `hasPath` and
    ///     `hops_to` are answered locally exactly as Python answers them.
    ///   - rpc: the management channel, non-nil only when attached as a local client.
    public init(transport: Transport, rpc: RPCClient? = nil) {
        self.transport = transport
        self.rpc = rpc
    }

    /// Python: `reticulum.is_connected_to_shared_instance` (rnprobe.py:166).
    ///
    /// The instance flag on `Transport`, not `Reticulum.isConnectedToSharedInstance()`,
    /// which answers "has any stack started in this process" and would make every probe
    /// take the RPC branch.
    public var isConnectedToSharedInstance: Bool { transport.isConnectedToSharedInstance }

    // MARK: Paths

    public func hasPath(to destinationHash: Data) -> Bool {
        transport.hasPath(to: destinationHash)
    }

    public func requestPath(for destinationHash: Data) {
        try? transport.requestPath(for: destinationHash)
    }

    /// Python: `RNS.Transport.hops_to(dh)` returns `PATHFINDER_M` (128) for an unknown
    /// destination, where Swift's `hopsTo` returns nil.
    public func hops(to destinationHash: Data) -> Int {
        guard let hops = transport.hopsTo(destinationHash) else { return Transport.pathfinderM }
        return Int(hops)
    }

    public func nextHop(to destinationHash: Data) -> Data? {
        if isConnectedToSharedInstance, let rpc {
            return try? rpc.nextHop(destinationHash: destinationHash)
        }
        return transport.nextHop(to: destinationHash)
    }

    /// Python: `str(RNS.Transport.next_hop_interface(dh))` — the interface's `__str__`.
    /// `Transport.nextHopInterfaceName(for:)` returns `Interface.name`, which is a
    /// different string, so the live object's `displayName` is used instead.
    public func nextHopInterfaceDisplayName(for destinationHash: Data) -> String? {
        if isConnectedToSharedInstance, let rpc {
            return try? rpc.nextHopInterfaceName(destinationHash: destinationHash)
        }
        return transport.nextHopInterface(for: destinationHash)?.displayName
    }

    /// Python: `Reticulum.get_first_hop_timeout` wraps the whole RPC call in try/except and
    /// returns `DEFAULT_PER_HOP_TIMEOUT` on any failure (Reticulum.py:1570-1572).
    public func firstHopTimeout(for destinationHash: Data) -> TimeInterval {
        if isConnectedToSharedInstance, let rpc {
            // `try?` on an optional-returning throwing call flattens, so this covers both
            // "the RPC threw" and "the daemon answered nil" with Python's 6.0 fallback.
            guard let value = try? rpc.firstHopTimeout(destinationHash: destinationHash) else {
                return Constants.defaultPerHopTimeout
            }
            return value
        }
        return transport.firstHopTimeout(for: destinationHash)
    }

    // MARK: Identity and ratchets

    /// Python: `RNS.Identity.recall(destination_hash)` (rnprobe.py:97).
    ///
    /// Goes through the `Transport` instance rather than the static
    /// `Identity.recall(destinationHash:)`, which delegates to `Reticulum.shared` and is
    /// therefore useless before `Reticulum.start()` has assigned it.
    public func recallIdentity(for destinationHash: Data) -> Identity? {
        transport.recall(identity: destinationHash)
    }

    public func currentRatchetKey(for destinationHash: Data) -> Data? {
        transport.currentRatchetKey(forDestination: destinationHash)
    }

    // MARK: Send

    /// Python: `RNS.Packet(request_destination, payload)` → `pack()` → `send()`.
    ///
    /// The MTU is enforced through `pack()` itself, not `Packet.rawByteCount` — the latter
    /// omits the one-byte context field and is a byte short of the real packed length.
    /// Defaults match Python's: DATA / SINGLE / HEADER_1 / BROADCAST / context NONE / hops 0.
    public func transmit(ciphertext: Data, to destinationHash: Data) throws -> (any ProbeReceipt)? {
        let packet = Packet(destinationType: .single,
                            packetType: .data,
                            destinationHash: destinationHash,
                            data: ciphertext)
        do {
            _ = try packet.pack()
        } catch Packet.PackError.exceedsMTU(let size) {
            throw NetworkProbe.SendError.mtuExceeded(size: size)
        }
        return try transport.send(packet)
    }

    // MARK: PHY stats

    /// Python: `reticulum.get_packet_rssi(packet_hash)` (rnprobe.py:167).
    ///
    /// Raw `MsgPack.Value` so the int-vs-float distinction Python's `str()` depends on
    /// survives; `RPCClient.packetRSSI` coerces through `asDouble` and would flatten it.
    public func packetRSSI(packetHash: Data) -> MsgPack.Value? {
        phyStat("packet_rssi", packetHash: packetHash) { transport.getPacketRssi(packetHash: $0) }
    }

    /// Python: `reticulum.get_packet_snr(packet_hash)` (rnprobe.py:168).
    public func packetSNR(packetHash: Data) -> MsgPack.Value? {
        phyStat("packet_snr", packetHash: packetHash) { transport.getPacketSnr(packetHash: $0) }
    }

    /// Python: `reticulum.get_packet_q(packet_hash)` (rnprobe.py:169).
    public func packetQ(packetHash: Data) -> MsgPack.Value? {
        phyStat("packet_q", packetHash: packetHash) { transport.getPacketQ(packetHash: $0) }
    }

    private func phyStat(_ call: String,
                         packetHash: Data,
                         local: (Data) -> Float?) -> MsgPack.Value? {
        if isConnectedToSharedInstance, let rpc {
            // Python always sends the FULL 32-byte hash. A Python daemon caches under that
            // key; a Swift daemon caches under the truncated one and narrows the key on
            // lookup, so the full hash works against both. The truncated retry keeps this
            // working against an older Swift daemon that does not narrow.
            if let value = try? rpc.get(call, extra: [("packet_hash", .bytes(packetHash))]),
               !isNil(value) {
                return value
            }
            let truncated = packetHash.prefix(Constants.truncatedHashLength)
            guard truncated.count != packetHash.count,
                  let value = try? rpc.get(call, extra: [("packet_hash", .bytes(truncated))]),
                  !isNil(value) else { return nil }
            return value
        }
        guard let value = local(packetHash) else { return nil }
        return .double(Double(value))
    }

    private func isNil(_ value: MsgPack.Value) -> Bool {
        if case .nil = value { return true }
        return false
    }
}

// MARK: - Clock

/// Python: `time.time()` and `time.sleep()`.
public final class SystemProbeClock: ProbeClock {
    public init() {}
    public func now() -> TimeInterval { Date().timeIntervalSince1970 }
    public func sleep(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        Thread.sleep(forTimeInterval: interval)
    }
}

// MARK: - Entropy

/// Python: `os.urandom(size)`.
///
/// `SecRandomCopyBytes` is the package's existing CSPRNG of choice; `UInt8.random(in:)`
/// is not cryptographically secure and would make probe payloads predictable.
public final class SecureProbeEntropy: ProbeEntropy {
    public init() {}
    public func randomBytes(_ count: Int) -> Data {
        guard count > 0 else { return Data() }
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            return Data((0..<count).map { _ in UInt8.random(in: 0...255) })
        }
        return bytes
    }
}

// MARK: - Output

/// Unbuffered stdout/stderr sink.
///
/// The tool emits bare `\r` and `\b` control characters with no newline, so every fragment
/// is flushed. Python only flushes at rnprobe.py:82, :90, :139 and :147 — flushing
/// everywhere changes on-screen timing, never the byte stream.
public final class StandardProbeOutput: ProbeOutput {
    public init() {}
    public func write(_ text: String) { fputs(text, stdout) }
    public func writeError(_ text: String) { fputs(text, stderr) }
    public func flush() { fflush(stdout); fflush(stderr) }
}
