import Foundation
import CryptoKit

// MARK: - WDCL Protocol Constants

/// Weave Device Control Layer packet-type byte values.
/// Python: `WDCL.WDCL_T_*`
public enum WDCL {
    /// Discovery broadcast.  Python: `WDCL_T_DISCOVER = 0x00`
    public static let tDiscover:    UInt8 = 0x00
    /// Connection handshake.  Python: `WDCL_T_CONNECT = 0x01`
    public static let tConnect:     UInt8 = 0x01
    /// Command frame.  Python: `WDCL_T_CMD = 0x02`
    public static let tCmd:         UInt8 = 0x02
    /// Log / event frame.  Python: `WDCL_T_LOG = 0x03`
    public static let tLog:         UInt8 = 0x03
    /// Display update frame.  Python: `WDCL_T_DISP = 0x04`
    public static let tDisp:        UInt8 = 0x04
    /// Endpoint packet (data plane).  Python: `WDCL_T_ENDPOINT_PKT = 0x05`
    public static let tEndpointPkt: UInt8 = 0x05
    /// Encapsulated protocol frame.  Python: `WDCL_T_ENCAP_PROTO = 0x06`
    public static let tEncapProto:  UInt8 = 0x06

    /// Broadcast destination address (4 × 0xFF).  Python: `WDCL_BROADCAST`
    public static let broadcast: Data = Data([0xFF, 0xFF, 0xFF, 0xFF])

    /// Minimum frame size: 4-byte switch_id + 1-byte type.  Python: `HEADER_MINSIZE = 4+1`
    public static let headerMinSize: Int = 5

    /// Seconds to wait for the WDCL handshake before giving up.  Python: `WDCL_HANDSHAKE_TIMEOUT = 2`
    public static let handshakeTimeout: TimeInterval = 2.0
}

// MARK: - Weave Command Codes

/// Two-byte command codes sent inside `WDCL_T_CMD` frames.
/// Python: `Cmd.*`
public enum WeaveCmd {
    /// Deliver a packet to a specific endpoint.  Python: `WDCL_CMD_ENDPOINT_PKT = 0x0001`
    public static let endpointPkt:    UInt16 = 0x0001
    /// Request a list of known endpoints.  Python: `WDCL_CMD_ENDPOINTS_LIST = 0x0100`
    public static let endpointsList:  UInt16 = 0x0100
    /// Enable / disable remote display output.  Python: `WDCL_CMD_REMOTE_DISPLAY = 0x0A00`
    public static let remoteDisplay:  UInt16 = 0x0A00
    /// Remote input command.  Python: `WDCL_CMD_REMOTE_INPUT = 0x0A01`
    public static let remoteInput:    UInt16 = 0x0A01
}

// MARK: - Weave Event Codes

/// 16-bit event codes carried inside `WDCL_T_LOG` frames.
/// Python: `Evt.*`
public enum WeaveEvt {
    public static let etMsg:                     UInt16 = 0x0000
    public static let etSystemBoot:              UInt16 = 0x0001
    public static let etCoreInit:                UInt16 = 0x0002
    public static let etBoardInit:               UInt16 = 0x0003   // Python (RNS 1.3.8): ET_BOARD_INIT
    public static let etDrvUartInit:             UInt16 = 0x1000
    public static let etDrvUsbCdcInit:           UInt16 = 0x1010
    public static let etDrvUsbCdcHostAvail:      UInt16 = 0x1011
    public static let etDrvUsbCdcConnected:      UInt16 = 0x1014
    public static let etDrvI2cInit:              UInt16 = 0x1020
    public static let etDrvNvsInit:              UInt16 = 0x1030
    public static let etDrvCryptoInit:           UInt16 = 0x1040
    public static let etDrvDisplayInit:          UInt16 = 0x1050
    public static let etDrvW80211Init:           UInt16 = 0x1060
    public static let etKrnLoggerInit:           UInt16 = 0x2000
    public static let etKrnUiInit:               UInt16 = 0x2010
    public static let etProtocolWdclInit:        UInt16 = 0x3000
    public static let etProtocolWdclRunning:     UInt16 = 0x3001
    /// Raised when WDCL connection is established.  Sets `wdclConnected = true`.
    public static let etProtocolWdclConnection:  UInt16 = 0x3002
    /// Raised when the remote device reports the host's endpoint ID.
    public static let etProtocolWdclHostEndpoint: UInt16 = 0x3003
    public static let etProtocolWeaveInit:       UInt16 = 0x3100
    public static let etProtocolWeaveRunning:    UInt16 = 0x3101
    /// Raised when a Weave endpoint is still alive.  Payload: 8-byte endpoint_id.
    public static let etProtocolWeaveEpAlive:    UInt16 = 0x3102
    /// Raised when a Weave endpoint has timed out.
    public static let etProtocolWeaveEpTimeout:  UInt16 = 0x3103
    /// Raised when a Weave endpoint route is known.  Payload: 8-byte endpoint_id + 4-byte switch_id.
    public static let etProtocolWeaveEpVia:      UInt16 = 0x3104
    public static let etSrvctlRemoteDisplay:     UInt16 = 0xA000
    public static let etInterfaceRegistered:     UInt16 = 0xD000
    public static let etStatState:               UInt16 = 0xE000
    public static let etStatUptime:              UInt16 = 0xE001
    public static let etStatCpu:                 UInt16 = 0xE003
    public static let etStatTaskCpu:             UInt16 = 0xE004
    public static let etStatMemory:              UInt16 = 0xE005
    public static let etStatStorage:             UInt16 = 0xE006
    public static let etSyserrMemExhausted:      UInt16 = 0xF000
}

// MARK: - WeaveLogFrame

/// A structured log / event frame received from a Weave device.
/// Python: `LogFrame`
public struct WeaveLogFrame {
    public let timestamp: TimeInterval   // seconds (raw value / 1000)
    public let level:     UInt8
    public let event:     UInt16
    public let data:      Data

    public init(timestamp: TimeInterval, level: UInt8, event: UInt16, data: Data) {
        self.timestamp = timestamp; self.level = level
        self.event = event; self.data = data
    }
}

// MARK: - WeaveEndpoint

/// Represents one remote endpoint (an RNS interface peer) discovered via a Weave switch.
/// Python: `WeaveEndpoint`
public final class WeaveEndpoint {
    /// Maximum number of packets held in the receive queue.  Python: `QUEUE_LEN = 1024`
    public static let queueLen: Int = 1024

    public let endpointAddr: Data
    public var lastSeen:     Date
    public var viaSwitchID:  Data?

    public init(endpointAddr: Data) {
        self.endpointAddr = endpointAddr
        self.lastSeen     = Date()
        self.viaSwitchID  = nil
    }
}

// MARK: - WDCLTransport

/// Handles the HDLC-framed serial connection to a Weave device.
///
/// Owns the `SerialPortTransport` and an `HDLC.FrameDecoder`.  Provides
/// helpers to send WDCL broadcast / unicast frames.  Feeds decoded HDLC
/// frames to a `WeaveDevice` state machine.
///
/// Python: the `WDCL` class (the serial + framing side of it).
public final class WDCLTransport {

    // MARK: - Class constants

    /// Baud rate for Weave devices.  Python: `self.speed = 3000000`
    public static let speed:         Int = 3_000_000

    /// Length of a switch_id in bytes.  Python: `WEAVE_SWITCH_ID_LEN = 4`
    public static let switchIDLen:   Int = 4

    /// Size of a Curve25519 public key.  Python: `WEAVE_PUBKEY_SIZE = 32`
    public static let pubkeySize:    Int = 32

    /// Length of an Ed25519 signature.  Python: `WEAVE_SIGNATURE_LEN = 64`
    public static let signatureLen:  Int = 64

    // MARK: - Identity

    /// Signing key that identifies this host on the Weave fabric.
    /// Python: `self.switch_identity = RNS.Identity()`
    private let signingKey:     Curve25519.Signing.PrivateKey

    /// Last 4 bytes of the signing public key — used as our switch_id.
    /// Python: `self.switch_id = self.switch_identity.sig_pub_bytes[-4:]`
    public  let switchID:       Data

    /// Full 32-byte signing public key.
    /// Python: `self.switch_pub_bytes = self.switch_identity.sig_pub_bytes`
    public  let switchPubBytes: Data

    // MARK: - Transport

    private let transport: SerialPortTransport
    private let decoder:   HDLC.FrameDecoder
    public  private(set) var isOnline: Bool = false

    /// Serializes the actual serial-port writes. Every outbound path (peer
    /// processOutgoing, discover/handshake/sendCommand) funnels through
    /// `processOutgoing`, so guarding it here makes all writes mutually exclusive
    /// and prevents two HDLC frames from interleaving byte-wise on the wire.
    private let writeLock = NSLock()

    // Back-reference (weak to break cycle)
    private weak var device: WeaveDevice?

    // MARK: - Init

    public init(transport: SerialPortTransport) {
        let key             = Curve25519.Signing.PrivateKey()
        self.signingKey     = key
        self.switchPubBytes = Data(key.publicKey.rawRepresentation)
        self.switchID       = Data(switchPubBytes.suffix(WDCLTransport.switchIDLen))
        self.transport      = transport
        self.decoder        = HDLC.FrameDecoder()
    }

    /// Wire in the `WeaveDevice` that will receive decoded frames.
    public func attach(device: WeaveDevice) { self.device = device }

    // MARK: - Port management

    public func open(port: String) throws {
        try transport.open(port: port, baudRate: WDCLTransport.speed,
                           dataBits: 8, parity: .none, stopBits: 1)
        transport.setReadCallback { [weak self] data in self?.feedBytes(data) }
        isOnline = true
    }

    public func close() {
        isOnline = false
        transport.close()
    }

    // MARK: - Outgoing

    /// HDLC-frame `data` and write to the serial port.
    /// Python: `WDCL.process_outgoing(data)`
    @discardableResult
    public func processOutgoing(_ data: Data) throws -> Int {
        writeLock.lock(); defer { writeLock.unlock() }
        let framed = HDLC.frame(data)
        return try transport.write(framed)
    }

    /// Sign `data` with our switch identity.
    /// Python: `self.switch_identity.sign(data)`
    public func sign(_ data: Data) -> Data {
        let sig = try! signingKey.signature(for: data)
        return Data(sig)
    }

    // MARK: - WDCL frame helpers

    /// Broadcast a WDCL frame to `0xFF FF FF FF`.
    /// Python: `self.device.wdcl_broadcast(packet_type, data)`
    public func broadcast(packetType: UInt8, data: Data) throws {
        var frame = WDCL.broadcast
        frame.append(packetType)
        frame.append(data)
        try processOutgoing(frame)
    }

    /// Send a WDCL unicast frame to `toSwitchID`.
    /// Python: `self.device.wdcl_send(packet_type, data)` (uses `self.switch_id` as dst)
    public func send(to toSwitchID: Data, packetType: UInt8, data: Data) throws {
        var frame = toSwitchID
        frame.append(packetType)
        frame.append(data)
        try processOutgoing(frame)
    }

    // MARK: - Incoming

    /// Feed raw bytes from the serial port through the HDLC decoder.
    private func feedBytes(_ raw: Data) {
        let frames = decoder.feed(raw)
        for frame in frames where frame.count >= WDCL.headerMinSize {
            device?.incomingFrame(frame)
        }
    }
}

// MARK: - WeaveDevice

/// Models a Weave switch device and implements the WDCL protocol state machine.
///
/// Handles discovery, handshake, endpoint tracking, and frame dispatch.
/// Python: `WeaveDevice`
public final class WeaveDevice {

    // MARK: - Class constants (wire sizes)

    /// Bytes in a switch_id.  Python: `WEAVE_SWITCH_ID_LEN = 4`
    public static let switchIDLen:   Int = 4
    /// Bytes in an endpoint_id.  Python: `WEAVE_ENDPOINT_ID_LEN = 8`
    public static let endpointIDLen: Int = 8
    /// Bytes in the flow-sequence field.  Python: `WEAVE_FLOWSEQ_LEN = 2`
    public static let flowseqLen:    Int = 2
    /// Bytes in the per-packet HMAC.  Python: `WEAVE_HMAC_LEN = 8`
    public static let hmacLen:       Int = 8
    /// Bytes in the full auth field.  Python: `WEAVE_AUTH_LEN = 16`
    public static let authLen:       Int = 16
    /// Bytes in a Curve25519 public key.  Python: `WEAVE_PUBKEY_SIZE = 32`
    public static let pubkeySize:    Int = 32
    /// Bytes in a Curve25519 private key.  Python: `WEAVE_PRVKEY_SIZE = 64`
    public static let prvkeySize:    Int = 64
    /// Bytes in an Ed25519 signature.  Python: `WEAVE_SIGNATURE_LEN = 64`
    public static let signatureLen:  Int = 64

    // MARK: - WDCL state

    /// The remote Weave device's switch_id (discovered during handshake).
    public internal(set) var switchID:      Data? = nil
    /// The host's own endpoint_id as reported by the device after connection.
    public internal(set) var endpointID:    Data? = nil
    /// True once the WDCL `ET_PROTO_WDCL_CONNECTION` event is received.
    public internal(set) var wdclConnected: Bool  = false

    // MARK: - Endpoint registry

    /// Serializes every access to `_endpoints`.
    ///
    /// The registry is mutated from the WDCL receive thread (`endpointAlive` /
    /// `endpointVia`, reached via `incomingFrame`) and both read and pruned
    /// from the periodic jobs thread (`WeaveInterface.peerJobs` →
    /// `pruneEndpoints`). Those run on *different* threads — the Python
    /// reference gets away with it under the GIL, but Swift has none, so an
    /// unsynchronized `Dictionary` here races and can crash ("Fatal error:
    /// Duplicate keys" / heap corruption). Every touch of `_endpoints` funnels
    /// through this lock.
    private let endpointsLock = NSLock()

    /// Backing store for the endpoint registry. Never touch directly — go
    /// through `endpoints` (reads) or the locked mutators below (writes).
    private var _endpoints: [Data: WeaveEndpoint] = [:]

    /// Snapshot of the endpoint registry, copied under `endpointsLock`.
    ///
    /// The returned dictionary is the caller's own value; the `WeaveEndpoint`
    /// instances it holds are never mutated in place after being inserted
    /// (see `endpointAlive` / `endpointVia`), so reading their fields off a
    /// snapshot is race-free even while the receive/jobs threads keep working.
    public var endpoints: [Data: WeaveEndpoint] {
        endpointsLock.lock(); defer { endpointsLock.unlock() }
        return _endpoints
    }

    // MARK: - Stats

    public private(set) var cpuLoad:  Double = 0.0
    public private(set) var memTotal: Int    = 0
    public private(set) var memFree:  Int    = 0
    public var memUsed: Int { max(0, memTotal - memFree) }

    // MARK: - Back-references (weak to break cycles)

    public weak var connection:    WDCLTransport?
    public weak var rnsInterface:  WeaveInterface?

    public init() {}

    // MARK: - Discovery / Handshake

    /// Send a WDCL DISCOVER broadcast containing our switch_id.
    /// Python: `WeaveDevice.discover()`
    public func discover() {
        guard let conn = connection else { return }
        try? conn.broadcast(packetType: WDCL.tDiscover, data: conn.switchID)
    }

    /// Send a WDCL CONNECT unicast to `switchID` carrying our pub-key + signature.
    /// Python: `WeaveDevice.handshake()`
    public func handshake() {
        guard let conn = connection, let remoteID = switchID else { return }
        let signature = conn.sign(remoteID)
        var payload   = conn.switchPubBytes
        payload.append(signature)
        try? conn.send(to: remoteID, packetType: WDCL.tConnect, data: payload)
    }

    // MARK: - Send helpers

    /// Build and send a WDCL command frame.
    /// Python: `WeaveDevice.wdcl_send_command(command, data)`
    public func sendCommand(command: UInt16, data: Data) {
        guard let remoteID = switchID, let conn = connection else { return }
        var frame = Data()
        frame.append(UInt8(command >> 8))
        frame.append(UInt8(command & 0xFF))
        frame.append(data)
        try? conn.send(to: remoteID, packetType: WDCL.tCmd, data: frame)
    }

    /// Instruct the device to deliver `data` to `endpointAddr`.
    /// Python: `WeaveDevice.deliver_packet(endpoint_id, data)`
    public func deliverPacket(endpointAddr: Data, data: Data) {
        var payload = endpointAddr
        payload.append(data)
        sendCommand(command: WeaveCmd.endpointPkt, data: payload)
    }

    // MARK: - Endpoint management

    /// Record that `endpointID` is alive and notify the parent interface.
    /// Python: `WeaveDevice.endpoint_alive(endpoint_id)`
    ///
    /// A refresh installs a *fresh* `WeaveEndpoint` rather than mutating the
    /// existing one in place: any snapshot handed out by `endpoints` keeps
    /// pointing at the old, now-immutable instance, so a concurrent reader
    /// never races our field write. The `rnsInterface` callback runs after
    /// the lock is released to avoid holding it across foreign code.
    public func endpointAlive(endpointID: Data) {
        endpointsLock.lock()
        if let existing = _endpoints[endpointID] {
            let refreshed = WeaveEndpoint(endpointAddr: endpointID)
            refreshed.viaSwitchID = existing.viaSwitchID   // carry the known route forward
            _endpoints[endpointID] = refreshed
        } else {
            _endpoints[endpointID] = WeaveEndpoint(endpointAddr: endpointID)
        }
        endpointsLock.unlock()
        rnsInterface?.addPeer(endpointAddr: endpointID)
    }

    /// Record the via-switch route for `endpointID`.
    /// Python: `WeaveDevice.endpoint_via(endpoint_id, via_switch_id)`
    ///
    /// Like `endpointAlive`, this replaces the record instead of mutating it
    /// in place, keeping previously handed-out snapshots immutable.
    public func endpointVia(endpointID: Data, viaSwitchID: Data) {
        endpointsLock.lock()
        if let existing = _endpoints[endpointID] {
            let updated = WeaveEndpoint(endpointAddr: endpointID)
            updated.lastSeen    = existing.lastSeen        // preserve liveness timestamp
            updated.viaSwitchID = viaSwitchID
            _endpoints[endpointID] = updated
        }
        endpointsLock.unlock()
        rnsInterface?.endpointVia(endpointAddr: endpointID, viaSwitchID: viaSwitchID)
    }

    /// Drop endpoints last heard from more than `timeout` seconds before `now`.
    ///
    /// The registry is otherwise append-only — the Python reference never
    /// prunes `WeaveDevice.endpoints`, so on a long-lived link it grows
    /// unbounded as endpoints come and go. `WeaveInterface.peerJobs()` calls
    /// this on the same `PEERING_TIMEOUT` it uses to expire peers, so the
    /// device registry and the interface peer table stay in lock-step.
    ///
    /// Internally synchronized (via `endpointsLock`), so it is safe to invoke
    /// from the jobs thread while the WDCL receive thread keeps learning
    /// endpoints. Wire-neutral: this touches only local bookkeeping.
    ///
    /// - Returns: the endpoint addresses that were removed.
    @discardableResult
    public func pruneEndpoints(olderThan timeout: TimeInterval, now: Date = Date()) -> [Data] {
        endpointsLock.lock(); defer { endpointsLock.unlock() }
        let expired = _endpoints.compactMap { addr, endpoint in
            now.timeIntervalSince(endpoint.lastSeen) > timeout ? addr : nil
        }
        for addr in expired { _endpoints.removeValue(forKey: addr) }
        return expired
    }

    /// An RNS packet arrived from `source` — deliver it to the interface.
    /// Python: `WeaveDevice.received_packet(source, data)`
    public func receivedPacket(source: Data, data: Data) {
        endpointAlive(endpointID: source)
        rnsInterface?.processIncoming(data: data, endpointAddr: source)
    }

    // MARK: - Frame dispatcher

    /// Dispatch an HDLC-decoded WDCL frame.
    ///
    /// Frame layout: `switch_id(4) + packet_type(1) + payload(…)`
    /// Python: `WeaveDevice.incoming_frame(data)`
    public func incomingFrame(_ data: Data) {
        guard data.count > WeaveDevice.switchIDLen + 1,
              let conn = connection else { return }

        let frameSwitchID = Data(data.prefix(WeaveDevice.switchIDLen))
        let packetType    = data[data.index(data.startIndex, offsetBy: WeaveDevice.switchIDLen)]
        let payload       = Data(data.dropFirst(WeaveDevice.switchIDLen + 1))

        switch packetType {

        // ── ENDPOINT_PKT: device → host (our packets arrive here) ────────────
        case WDCL.tEndpointPkt where frameSwitchID == conn.switchID:
            // layout: rns_data + src_endpoint_id(8)
            guard payload.count > WeaveDevice.endpointIDLen else { return }
            let rnsData     = Data(payload.dropLast(WeaveDevice.endpointIDLen))
            let srcEndpoint = Data(payload.suffix(WeaveDevice.endpointIDLen))
            receivedPacket(source: srcEndpoint, data: rnsData)

        // ── DISCOVER response: device → host ─────────────────────────────────
        case WDCL.tDiscover:
            // Expected: switch_id(4) + type(1) + pub_key(32) + signature(64) = 101 bytes
            let expectedLen = WeaveDevice.switchIDLen + 1
                            + WeaveDevice.pubkeySize + WeaveDevice.signatureLen
            guard data.count == expectedLen else { return }

            let signedID       = Data(frameSwitchID)
            let pubStart       = WeaveDevice.switchIDLen + 1
            let remotePubBytes = Data(data[pubStart ..< pubStart + WeaveDevice.pubkeySize])
            let remoteSwitchID = Data(remotePubBytes.suffix(WeaveDevice.switchIDLen))
            let remoteSig      = Data(data.suffix(WeaveDevice.signatureLen))

            guard let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: remotePubBytes),
                  pubKey.isValidSignature(remoteSig, for: signedID) else { return }

            switchID = remoteSwitchID
            handshake()

        // ── LOG / EVENT frame ────────────────────────────────────────────────
        case WDCL.tLog:
            // layout: type(1) + ts_high(1) + ts_bytes(4) + level(1) + evt_hi(1) + evt_lo(1) + data
            guard payload.count >= 8 else { return }
            let ts  = UInt32(payload[1]) << 24 | UInt32(payload[2]) << 16
                    | UInt32(payload[3]) << 8  | UInt32(payload[4])
            let lvl = payload[5]
            let evt = UInt16(payload[6]) << 8 | UInt16(payload[7])
            let frameData = payload.count > 8 ? Data(payload.dropFirst(8)) : Data()
            handleLog(WeaveLogFrame(timestamp: Double(ts) / 1000.0,
                                    level: lvl, event: evt, data: frameData))

        default:
            break
        }
    }

    // MARK: - Log handler

    /// Handle a structured log / event frame.
    /// Python: `WeaveDevice.log_handle(frame)`
    public func handleLog(_ frame: WeaveLogFrame) {
        switch frame.event {

        case WeaveEvt.etProtocolWdclConnection:
            wdclConnected = true

        case WeaveEvt.etProtocolWdclHostEndpoint
             where frame.data.count == WeaveDevice.endpointIDLen:
            endpointID = frame.data

        case WeaveEvt.etProtocolWeaveEpAlive
             where frame.data.count == WeaveDevice.endpointIDLen:
            endpointAlive(endpointID: frame.data)

        case WeaveEvt.etProtocolWeaveEpVia
             where frame.data.count == WeaveDevice.endpointIDLen + WeaveDevice.switchIDLen:
            let epID = Data(frame.data.prefix(WeaveDevice.endpointIDLen))
            let swID = Data(frame.data.suffix(WeaveDevice.switchIDLen))
            endpointVia(endpointID: epID, viaSwitchID: swID)

        case WeaveEvt.etStatCpu:
            cpuLoad = frame.data.isEmpty ? 0.0 : Double(frame.data[frame.data.startIndex])

        case WeaveEvt.etStatMemory where frame.data.count >= 8:
            memFree  = Int(UInt32(frame.data[0]) << 24 | UInt32(frame.data[1]) << 16
                         | UInt32(frame.data[2]) << 8  | UInt32(frame.data[3]))
            memTotal = Int(UInt32(frame.data[4]) << 24 | UInt32(frame.data[5]) << 16
                         | UInt32(frame.data[6]) << 8  | UInt32(frame.data[7]))

        default:
            break
        }
    }
}

// MARK: - WeaveInterface

/// RNS interface for Weave switch devices.
///
/// Manages a WDCL serial connection, maintains a peer table, and spawns
/// one `WeaveInterfacePeer` per discovered endpoint.
///
/// Python: `WeaveInterface`
public final class WeaveInterface: Interface {

    // MARK: - Class constants

    /// Maximum payload the hardware can carry.  Python: `HW_MTU = 1024`
    public static let hwMtuValue:      Int          = 1024
    /// Default IFAC frame size.  Python: `DEFAULT_IFAC_SIZE = 16`
    public static let defaultIfacSize: Int          = 16
    /// Seconds before a silent peer is declared timed out.  Python: `PEERING_TIMEOUT = 20.0`
    public static let peeringTimeout:  TimeInterval = 20.0
    /// Estimated line rate.  Python: `BITRATE_GUESS = 250*1000`
    public static let bitrateGuess:    Int          = 250_000
    /// Duplicate-suppression time window in seconds.  Python: `MULTI_IF_DEQUE_TTL = 0.75`
    public static let multiIfDequeTTL: TimeInterval = 0.75
    /// Maximum number of packet hashes held in the dedup deque.  Python: `MULTI_IF_DEQUE_LEN = 48`
    public static let multiIfDequeLen: Int          = 48

    // MARK: - Interface protocol

    public let  name:    String
    public var  bitrate: Int = WeaveInterface.bitrateGuess

    public private(set) var isOnline:  Bool = false

    public private(set) var rxBytes:   Int = 0
    public private(set) var txBytes:   Int = 0
    public private(set) var rxPackets: Int = 0
    public private(set) var txPackets: Int = 0

    public var hwMtu:           Int? { WeaveInterface.hwMtuValue }
    public var inboundHandler:  ((Packet, any Interface) -> Void)? = nil
    public var rawInboundHandler: ((Data, any Interface) -> Void)? = nil

    public var ifacIdentity: Identity? = nil
    public var ifacKey:      Data?     = nil
    public var ifacSize:     Int       = WeaveInterface.defaultIfacSize

    public var wantsTunnel: Bool  = false
    public var tunnelID:    Data? = nil

    // MARK: - Weave state

    public let port: String

    /// WDCL serial transport (HDLC framing + signing key).
    public let wdclTransport: WDCLTransport

    /// Protocol state machine for the attached Weave device.
    public let device: WeaveDevice

    /// Lock protecting outgoing writes from concurrent `WeaveInterfacePeer` calls.
    internal let writeLock = NSLock()

    // MARK: - Peer management

    /// Live endpoint → last-seen record.
    public private(set) var peers: [Data: WeaveEndpoint] = [:]

    /// Endpoint → spawned peer interface.
    public private(set) var spawnedInterfaces: [Data: WeaveInterfacePeer] = [:]

    // MARK: - Duplicate-packet suppression

    /// Ordered list of packet-hash entries (bounded by `multiIfDequeLen`).
    internal var mifDeque:      [Data]        = []
    /// packet_hash → time-of-first-seen (for TTL check).
    internal var mifDequeTimes: [Data: Date]  = [:]

    // MARK: - Injection points for Transport integration / tests

    /// Called when a new `WeaveInterfacePeer` is spawned.  Register with Transport here.
    public var onPeerAdded:   ((WeaveInterfacePeer) -> Void)? = nil
    /// Called when a peer is timed out and removed.  De-register from Transport here.
    public var onPeerRemoved: ((WeaveInterfacePeer) -> Void)? = nil

    // MARK: - Init

    public init(name: String, port: String, transport: SerialPortTransport) {
        self.name          = name
        self.port          = port
        let wt             = WDCLTransport(transport: transport)
        self.wdclTransport = wt
        let dev            = WeaveDevice()
        self.device        = dev

        // Wire: transport → device → interface (all weak to break cycles)
        wt.attach(device: dev)
        dev.connection   = wt
        dev.rnsInterface = nil  // set below after self is initialized
    }

    // Called after init to close the circular reference
    // (cannot set in init body because WeaveDevice.rnsInterface is weak var to WeaveInterface)

    /// Bring the interface online: open the serial port and initiate discovery.
    public func start() throws {
        device.rnsInterface = self
        try wdclTransport.open(port: port)
        isOnline = true
        device.discover()
    }

    /// Take the interface offline and close the serial port.
    public func stop() {
        isOnline = false
        device.rnsInterface = nil
        wdclTransport.close()
    }

    // MARK: - Peer management

    /// Register a new endpoint peer or refresh an existing one.
    /// Called by `WeaveDevice.endpointAlive()`.
    /// Python: `WeaveInterface.add_peer(endpoint_addr)`
    public func addPeer(endpointAddr: Data) {
        guard peers[endpointAddr] == nil else {
            refreshPeer(endpointAddr: endpointAddr)
            return
        }
        let peer = WeaveInterfacePeer(owner: self, endpointAddr: endpointAddr)
        peer.bitrate = bitrate
        spawnedInterfaces[endpointAddr] = peer
        peers[endpointAddr]             = WeaveEndpoint(endpointAddr: endpointAddr)
        onPeerAdded?(peer)
    }

    /// Update the last-seen timestamp for `endpointAddr`.
    /// Python: `WeaveInterface.refresh_peer(endpoint_addr)`
    public func refreshPeer(endpointAddr: Data) {
        peers[endpointAddr]?.lastSeen = Date()
    }

    /// Update the via-switch route for a peer.
    /// Python: `WeaveInterface.endpoint_via(endpoint_addr, via_switch_addr)`
    public func endpointVia(endpointAddr: Data, viaSwitchID: Data) {
        spawnedInterfaces[endpointAddr]?.viaSwitchID = viaSwitchID
    }

    /// Route an inbound packet from the device to the appropriate peer interface.
    /// Python: `WeaveInterface.process_incoming(data, endpoint_addr)`
    public func processIncoming(data: Data, endpointAddr: Data) {
        guard isOnline, let peer = spawnedInterfaces[endpointAddr] else { return }
        peer.processIncoming(data: data, endpointAddr: endpointAddr)
    }

    /// Not used on the parent interface — peers handle outgoing traffic.
    public func send(_ packet: Packet) throws {}
    public func processOutgoing(_ data: Data) {}

    // MARK: - Peer count

    /// Number of currently active peer interfaces.
    /// Python: `WeaveInterface.peer_count`
    public var peerCount: Int { spawnedInterfaces.count }

    // MARK: - Internal helpers (used by WeaveInterfacePeer)

    /// Accumulate inbound statistics on behalf of a child peer.
    internal func addRxStats(bytes: Int) { rxBytes += bytes; rxPackets += 1 }

    /// Accumulate outbound statistics on behalf of a child peer.
    internal func addTxStats(bytes: Int) { txBytes += bytes; txPackets += 1 }

    /// Remove a peer's table entries (called from `WeaveInterfacePeer.teardown()`).
    internal func removePeerEntry(endpointAddr: Data) {
        spawnedInterfaces.removeValue(forKey: endpointAddr)
        peers.removeValue(forKey: endpointAddr)
    }

    // MARK: - Peer timeout job

    /// Remove any peers that haven't been heard from in `peeringTimeout` seconds.
    /// Called periodically (e.g. every `PEERING_TIMEOUT × 1.1` seconds).
    /// Python: `WeaveInterface.peer_jobs()`
    public func peerJobs() {
        let now     = Date()
        var expired = [Data]()
        for (addr, endpoint) in peers {
            if now.timeIntervalSince(endpoint.lastSeen) > WeaveInterface.peeringTimeout {
                expired.append(addr)
            }
        }
        for addr in expired {
            if let spawned = spawnedInterfaces[addr] {
                onPeerRemoved?(spawned)
                spawnedInterfaces.removeValue(forKey: addr)
            }
            peers.removeValue(forKey: addr)
        }

        // Prune the device's endpoint registry on the same timeout and `now`,
        // so it stays in lock-step with the peer table instead of growing
        // unbounded. `pruneEndpoints` is internally synchronized, so this is
        // safe to call from the jobs thread while the WDCL receive thread is
        // still learning endpoints.
        device.pruneEndpoints(olderThan: WeaveInterface.peeringTimeout, now: now)
    }
}

// MARK: - WeaveInterfacePeer

/// A per-endpoint child interface spawned by `WeaveInterface`.
///
/// Outgoing packets are routed through the parent's `WeaveDevice` to the
/// remote endpoint.  Incoming packets are deduplicated (time-windowed) and
/// forwarded to `rawInboundHandler`.
///
/// Python: `WeaveInterfacePeer`
public final class WeaveInterfacePeer: Interface {

    // MARK: - Interface protocol

    public let  name:    String
    public var  bitrate: Int = WeaveInterface.bitrateGuess

    public private(set) var isOnline: Bool = true

    public private(set) var rxBytes:   Int = 0
    public private(set) var txBytes:   Int = 0
    public private(set) var rxPackets: Int = 0
    public private(set) var txPackets: Int = 0

    public var hwMtu:             Int? { owner?.hwMtu }
    public var inboundHandler:    ((Packet, any Interface) -> Void)? = nil
    public var rawInboundHandler: ((Data,   any Interface) -> Void)? = nil

    public var ifacIdentity: Identity? = nil
    public var ifacKey:      Data?     = nil
    public var ifacSize:     Int       = WeaveInterface.defaultIfacSize

    public var wantsTunnel: Bool  = false
    public var tunnelID:    Data? = nil

    // MARK: - Peer metadata

    /// The remote endpoint's 8-byte address.
    public let endpointAddr: Data
    /// Optional switch_id through which this endpoint is reachable.
    public var viaSwitchID:  Data? = nil

    /// The parent WeaveInterface's device switch ID (mirrors Python `peer.switch_id`).
    public var switchID: Data? { owner?.device.switchID }
    /// The endpoint ID for this peer, derived from the endpoint address.
    /// Mirrors Python `peer.endpoint_id` — the 8-byte endpoint address.
    public var endpointID: Data? { endpointAddr }

    // MARK: - Back-reference

    public weak var owner: WeaveInterface?

    private let lock = NSLock()

    // MARK: - Init

    init(owner: WeaveInterface, endpointAddr: Data) {
        self.owner        = owner
        self.endpointAddr = endpointAddr
        self.name         = "WeaveInterfacePeer[\(endpointAddr.map { String(format: "%02x", $0) }.joined())]"
        self.bitrate      = owner.bitrate
    }

    // MARK: - Incoming

    /// Deduplicate and deliver an inbound RNS packet.
    ///
    /// Uses a time-windowed hash deque shared on the parent interface to
    /// suppress duplicates arriving via multiple paths.
    ///
    /// Python: `WeaveInterfacePeer.process_incoming(data, endpoint_addr)`
    public func processIncoming(data: Data, endpointAddr: Data?) {
        guard isOnline, let owner = owner else { return }

        // Time-windowed duplicate detection
        let dataHash = Hashes.fullHash(data)
        lock.lock()
        let now = Date()
        var isDuplicate = false
        if let firstSeen = owner.mifDequeTimes[dataHash],
           now.timeIntervalSince(firstSeen) < WeaveInterface.multiIfDequeTTL {
            isDuplicate = true
        } else {
            owner.mifDeque.append(dataHash)
            owner.mifDequeTimes[dataHash] = now
            // Prune oldest entry when over capacity
            if owner.mifDeque.count > WeaveInterface.multiIfDequeLen {
                let removed = owner.mifDeque.removeFirst()
                owner.mifDequeTimes.removeValue(forKey: removed)
            }
        }
        lock.unlock()
        guard !isDuplicate else { return }

        owner.refreshPeer(endpointAddr: self.endpointAddr)
        rxBytes   += data.count
        rxPackets += 1
        owner.addRxStats(bytes: data.count)
        rawInboundHandler?(data, self)
    }

    // MARK: - Outgoing

    /// Route an outgoing RNS packet through the parent's Weave device.
    ///
    /// Python: `WeaveInterfacePeer.process_outgoing(data)`
    public func processOutgoing(_ data: Data) {
        guard isOnline, let owner = owner else { return }
        owner.writeLock.lock()
        owner.device.deliverPacket(endpointAddr: endpointAddr, data: data)
        owner.writeLock.unlock()
        txBytes   += data.count
        txPackets += 1
        owner.addTxStats(bytes: data.count)
    }

    // MARK: - Send (Interface protocol)

    /// Pack `packet` and route through the parent Weave device.
    public func send(_ packet: Packet) throws {
        guard let raw = try? packet.pack() else { return }
        processOutgoing(raw)
    }

    // MARK: - Lifecycle

    /// Peers come online when spawned; `start()` is a no-op.
    public func start() throws {}
    /// Take peer offline; equivalent to `detach()`.
    public func stop() { isOnline = false }

    /// Mark this peer as offline (but leave it in the parent's table).
    public func detach() { isOnline = false }

    /// Mark offline and remove from the parent's spawned-interfaces table.
    /// Python: `WeaveInterfacePeer.teardown()`
    public func teardown() {
        isOnline = false
        owner?.removePeerEntry(endpointAddr: endpointAddr)
    }
}
