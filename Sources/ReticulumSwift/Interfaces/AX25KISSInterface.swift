import Foundation

// MARK: - AX25

/// AX.25 frame constants.
/// Mirrors the `AX25` class in Python `AX25KISSInterface.py`.
public struct AX25 {
    /// No-layer-3 protocol identifier.  Python: `PID_NOLAYER3 = 0xF0`
    public static let pidNoLayer3: UInt8 = 0xF0

    /// Unnumbered Information control field.  Python: `CTRL_UI = 0x03`
    public static let ctrlUI: UInt8 = 0x03

    /// AX.25 frame-check-sequence bytes (reference only; not validated here).
    /// Python: `CRC_CORRECT = bytes([0xF0])+bytes([0xB8])`
    public static let crcCorrect: Data = Data([0xF0, 0xB8])

    /// Size of the AX.25 header prepended to every packet:
    /// 7 (dst addr+ssid) + 7 (src addr+ssid) + 1 (CTRL_UI) + 1 (PID) = 16.
    /// Python: `HEADER_SIZE = 16`
    public static let headerSize: Int = 16

    /// Destination callsign used for all Reticulum-over-AX25 frames.
    /// Python: `self.dst_call = "APZRNS".encode("ascii")`
    public static let dstCallsign: String = "APZRNS"

    /// Encode a 6-character (padded) AX.25 callsign + SSID into 7 bytes.
    ///
    /// Each character is left-shifted 1 bit.  Padding is ASCII space (0x20)
    /// left-shifted (0x40).  The SSID byte is `0x60 | (ssid << 1)`,
    /// plus `0x01` (end-of-address bit) when `endOfAddress = true`.
    public static func encodeAddress(callsign: String,
                                     ssid: Int,
                                     endOfAddress: Bool) -> Data {
        var out = Data(capacity: 7)
        let bytes = Array(callsign.utf8)
        for i in 0..<6 {
            let b: UInt8 = i < bytes.count ? bytes[i] : 0x20  // pad with space
            out.append(b << 1)
        }
        var ssidByte: UInt8 = 0x60 | UInt8(ssid << 1)
        if endOfAddress { ssidByte |= 0x01 }
        out.append(ssidByte)
        return out
    }
}

// MARK: - Errors

public enum AX25KISSInterfaceError: Error {
    case invalidCallsign(String)
    case invalidSSID(Int)
    case portOpenFailed(String)
}

// MARK: - AX25KISSInterface

/// AX.25 KISS interface: wraps every Reticulum packet in an AX.25 UI frame
/// before KISS-framing and sending over a serial port.
///
/// Wire-compatible with Python `RNS/Interfaces/AX25KISSInterface.py`.
public final class AX25KISSInterface: Interface {

    // MARK: - Class constants

    /// Python: `BITRATE_GUESS = 1200`
    public static let bitrateGuess: Int = 1_200

    /// Python: `DEFAULT_IFAC_SIZE = 8`
    public static let defaultIfacSize: Int = 8

    /// Python: `self.HW_MTU = 564`
    public static let hwMtuConstant: Int = 564

    // MARK: - Interface protocol properties

    public let  name:    String
    public var  bitrate: Int = AX25KISSInterface.bitrateGuess
    private let onlineFlag = LockedFlag(false)
    public private(set) var isOnline: Bool {
        get { onlineFlag.value }
        set { onlineFlag.value = newValue }
    }

    /// Lock-guarded — written from this interface's I/O queue while the UI
    /// and status reporting read from another thread. See `InterfaceCounters`.
    private let counters = InterfaceCounters()
    public var rxBytes:   Int { counters.rxBytes }
    public var txBytes:   Int { counters.txBytes }
    public var rxPackets: Int { counters.rxPackets }
    public var txPackets: Int { counters.txPackets }

    public var hwMtu: Int? { AX25KISSInterface.hwMtuConstant }

    public var inboundHandler:    ((Packet, any Interface) -> Void)? = nil
    public var rawInboundHandler: ((Data,   any Interface) -> Void)? = nil

    public var ifacIdentity: Identity? = nil
    public var ifacKey:      Data?     = nil
    public var ifacSize:     Int       = AX25KISSInterface.defaultIfacSize

    public var wantsTunnel: Bool  = false
    public var tunnelID:    Data? = nil

    // MARK: - AX.25 configuration

    /// Source callsign (uppercased, 3–6 characters).
    public let srcCallsign: String

    /// Source SSID (0–15).
    public let srcSSID: Int

    // MARK: - Serial / KISS configuration

    public let port:     String
    public let speed:    Int
    public let dataBits: Int
    public let parity:   SerialParity
    public let stopBits: Int

    public var preamble:    Int  = 350
    public var txtail:      Int  = 20
    public var persistence: Int  = 64
    public var slottime:    Int  = 20
    public var flowControl: Bool = false

    // MARK: - Flow control state

    public private(set) var interfaceReady: Bool = false
    private var packetQueue: [Data] = []
    private let lock = NSLock()

    // MARK: - Private

    private let transport: SerialPortTransport
    private let decoder = KISS.FrameDecoder()

    // MARK: - Init

    /// - Throws: `AX25KISSInterfaceError.invalidCallsign` if `callsign` is not 3–6 characters.
    ///           `AX25KISSInterfaceError.invalidSSID` if `ssid` is not 0–15.
    public init(name:     String,
                port:     String,
                speed:    Int          = 9600,
                dataBits: Int          = 8,
                parity:   SerialParity = .none,
                stopBits: Int          = 1,
                callsign: String,
                ssid:     Int,
                preamble:    Int  = 350,
                txtail:      Int  = 20,
                persistence: Int  = 64,
                slottime:    Int  = 20,
                flowControl: Bool = false,
                transport: SerialPortTransport) throws {
        guard callsign.count >= 3 && callsign.count <= 6 else {
            throw AX25KISSInterfaceError.invalidCallsign(callsign)
        }
        guard ssid >= 0 && ssid <= 15 else {
            throw AX25KISSInterfaceError.invalidSSID(ssid)
        }
        self.name        = name
        self.port        = port
        self.speed       = speed
        self.dataBits    = dataBits
        self.parity      = parity
        self.stopBits    = stopBits
        self.srcCallsign = callsign.uppercased()
        self.srcSSID     = ssid
        self.preamble    = preamble
        self.txtail      = txtail
        self.persistence = persistence
        self.slottime    = slottime
        self.flowControl = flowControl
        self.transport   = transport
    }

    /// Convenience init with string parity (INI config: "N", "E", "O").
    public convenience init(name:         String,
                            port:         String,
                            speed:        Int    = 9600,
                            dataBits:     Int    = 8,
                            parityString: String,
                            stopBits:     Int    = 1,
                            callsign: String,
                            ssid:     Int,
                            preamble:    Int  = 350,
                            txtail:      Int  = 20,
                            persistence: Int  = 64,
                            slottime:    Int  = 20,
                            flowControl: Bool = false,
                            transport: SerialPortTransport) throws {
        try self.init(name: name, port: port,
                      speed: speed, dataBits: dataBits,
                      parity: SerialParity(string: parityString), stopBits: stopBits,
                      callsign: callsign, ssid: ssid,
                      preamble: preamble, txtail: txtail,
                      persistence: persistence, slottime: slottime,
                      flowControl: flowControl, transport: transport)
    }

    // MARK: - Interface lifecycle

    public func start() throws {
        try transport.open(port: port, baudRate: speed,
                           dataBits: dataBits, parity: parity, stopBits: stopBits)
        transport.setReadCallback { [weak self] data in
            self?.feedBytes(data)
        }
        lock.lock(); isOnline = true; lock.unlock()
        sendKISSConfig()
        lock.lock(); interfaceReady = true; lock.unlock()
    }

    public func stop() {
        lock.lock()
        isOnline       = false
        interfaceReady = false
        lock.unlock()
        transport.close()
    }

    // MARK: - KISS TNC configuration (same as KISSInterface)

    private func sendKISSConfig() {
        setPreamble(preamble)
        setTxTail(txtail)
        setPersistence(persistence)
        setSlotTime(slottime)
        setFlowControl(flowControl)
    }

    public func setPreamble(_ p: Int) {
        let v = max(0, min(255, p / 10))
        try? transport.write(Data([KISS.fend, KISS.cmdTxDelay, UInt8(v), KISS.fend]))
    }
    public func setTxTail(_ t: Int) {
        let v = max(0, min(255, t / 10))
        try? transport.write(Data([KISS.fend, KISS.cmdTxTail, UInt8(v), KISS.fend]))
    }
    public func setPersistence(_ p: Int) {
        let v = UInt8(max(0, min(255, p)))
        try? transport.write(Data([KISS.fend, KISS.cmdP, v, KISS.fend]))
    }
    public func setSlotTime(_ s: Int) {
        let v = max(0, min(255, s / 10))
        try? transport.write(Data([KISS.fend, KISS.cmdSlotTime, UInt8(v), KISS.fend]))
    }
    public func setFlowControl(_ enabled: Bool) {
        try? transport.write(Data([KISS.fend, KISS.cmdReady, 0x01, KISS.fend]))
    }

    // MARK: - Outgoing

    /// Send a Reticulum packet.  Called by Transport.
    ///
    /// Applies the IFAC mask (when an IFAC key is configured) to the packet
    /// before the AX.25 header is prepended and the frame is KISS-escaped,
    /// mirroring Python `Transport.transmit` (IFAC is applied to the raw packet,
    /// then `process_outgoing` builds the AX.25 UI frame around the masked
    /// bytes). Without this, frames go out un-masked and IFAC-protected Python
    /// peers drop them.
    public func send(_ packet: Packet) throws {
        guard let raw = try? packet.pack() else { return }
        processOutgoing(wrapIfac(raw))
    }

    /// Prepend AX.25 header, KISS-frame, and write to the TNC.
    ///
    /// Python: `process_outgoing(data)` — builds AX.25 UI frame then KISS-escapes.
    public func processOutgoing(_ data: Data) {
        // Decide send-vs-enqueue atomically under `lock` (see KISSInterface):
        // `interfaceReady` and `packetQueue` are one flow-control state.
        lock.lock()
        guard isOnline else { lock.unlock(); return }
        if interfaceReady {
            if flowControl { interfaceReady = false }
            lock.unlock()

            // Build AX.25 address field
            let dstAddr = AX25.encodeAddress(callsign: AX25.dstCallsign,
                                             ssid: 0,
                                             endOfAddress: false)
            let srcAddr = AX25.encodeAddress(callsign: srcCallsign,
                                             ssid: srcSSID,
                                             endOfAddress: true)

            // AX.25 UI frame: addr + CTRL_UI + PID + data
            var ax25 = Data()
            ax25.append(dstAddr)
            ax25.append(srcAddr)
            ax25.append(AX25.ctrlUI)
            ax25.append(AX25.pidNoLayer3)
            ax25.append(data)

            let framed = KISS.frame(ax25)
            try? transport.write(framed)
            counters.addTx(bytes: data.count)   // Python counts original payload
        } else {
            packetQueue.append(data)
            lock.unlock()
        }
    }

    public func processQueue() {
        lock.lock()
        guard !packetQueue.isEmpty else {
            interfaceReady = true
            lock.unlock()
            return
        }
        let next = packetQueue.removeFirst()
        interfaceReady = true
        lock.unlock()
        processOutgoing(next)
    }

    // MARK: - Incoming

    /// Feed raw bytes from the serial port.
    ///
    /// AX.25 header (first `AX25.headerSize` bytes) is stripped before
    /// delivering to the inbound handler.
    ///
    /// Python: `process_incoming` strips header and calls `owner.inbound`.
    public func feedBytes(_ data: Data) {
        let frames = decoder.feed(data)
        for (cmd, payload) in frames {
            if cmd == KISS.cmdData {
                guard payload.count > AX25.headerSize else { continue }
                let stripped = payload.dropFirst(AX25.headerSize)
                counters.addRx(bytes: payload.count)   // Python counts full payload incl. header
                rawInboundHandler?(Data(stripped), self)
            } else if cmd == KISS.cmdReady {
                processQueue()
            }
        }
    }

    // MARK: - Queue inspection (for tests)

    public var queuedPacketCount: Int {
        lock.lock(); defer { lock.unlock() }
        return packetQueue.count
    }
}
