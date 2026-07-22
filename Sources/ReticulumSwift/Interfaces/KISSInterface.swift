import Foundation

// MARK: - Errors

public enum KISSInterfaceError: Error {
    case portNotFound(String)
    case portOpenFailed(String)
    case configWriteError(String)
}

// MARK: - KISSInterface

/// KISS TNC interface over a serial port.
///
/// Wire-compatible with Python `RNS/Interfaces/KISSInterface.py`.
/// Supports optional flow-control (CMD_READY handshake) and beacon transmission.
///
/// Like `SerialInterface`, the physical serial port is injected via
/// `SerialPortTransport` so the interface is unit-testable without hardware.
public final class KISSInterface: Interface {

    // MARK: - Class constants

    /// Python: `BITRATE_GUESS = 1200`
    public static let bitrateGuess: Int = 1_200

    /// Python: `DEFAULT_IFAC_SIZE = 8`
    public static let defaultIfacSize: Int = 8

    /// Python: `self.HW_MTU = 564`
    public static let hwMtuConstant: Int = 564

    // MARK: - Interface protocol properties

    public let  name:    String
    public var  bitrate: Int = KISSInterface.bitrateGuess
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

    public var hwMtu: Int? { KISSInterface.hwMtuConstant }

    public var inboundHandler:    ((Packet, any Interface) -> Void)? = nil
    public var rawInboundHandler: ((Data,   any Interface) -> Void)? = nil

    public var ifacIdentity: Identity? = nil
    public var ifacKey:      Data?     = nil
    public var ifacSize:     Int       = KISSInterface.defaultIfacSize

    public var wantsTunnel: Bool  = false
    public var tunnelID:    Data? = nil

    // MARK: - Serial configuration

    public let port:     String
    public let speed:    Int
    public let dataBits: Int
    public let parity:   SerialParity
    public let stopBits: Int

    // MARK: - KISS configuration (Python defaults)

    /// Preamble in milliseconds.  Python default: `350`.
    public var preamble:     Int = 350
    /// TX tail in milliseconds.  Python default: `20`.
    public var txtail:       Int = 20
    /// Persistence (0–255).  Python default: `64`.
    public var persistence:  Int = 64
    /// Slot time in milliseconds.  Python default: `20`.
    public var slottime:     Int = 20
    /// Whether to use hardware flow control (CMD_READY handshake).
    public var flowControl:  Bool = false

    // MARK: - Beacon configuration

    /// Seconds between beacon transmissions (nil = disabled).
    public var beaconInterval: TimeInterval? = nil
    /// Raw bytes sent as beacon payload.
    public var beaconData: Data = Data()

    // MARK: - Flow control state

    /// True when the TNC is ready to accept the next frame.
    /// Set to false after sending when `flowControl = true`; restored on CMD_READY.
    public private(set) var interfaceReady: Bool = false

    // MARK: - Packet queue (used when flowControl=true and TNC is busy)

    private var packetQueue: [Data] = []

    // MARK: - Private

    private let transport: SerialPortTransport
    private let decoder = KISS.FrameDecoder()
    private let lock    = NSLock()

    // MARK: - Init

    public init(name:     String,
                port:     String,
                speed:    Int          = 9600,
                dataBits: Int          = 8,
                parity:   SerialParity = .none,
                stopBits: Int          = 1,
                preamble:    Int  = 350,
                txtail:      Int  = 20,
                persistence: Int  = 64,
                slottime:    Int  = 20,
                flowControl: Bool = false,
                beaconInterval: TimeInterval? = nil,
                beaconData:     String        = "",
                transport: SerialPortTransport) {
        self.name        = name
        self.port        = port
        self.speed       = speed
        self.dataBits    = dataBits
        self.parity      = parity
        self.stopBits    = stopBits
        self.preamble    = preamble
        self.txtail      = txtail
        self.persistence = persistence
        self.slottime    = slottime
        self.flowControl = flowControl
        self.beaconInterval = beaconInterval
        self.beaconData  = Data(beaconData.utf8)
        self.transport   = transport
    }

    /// Convenience init that parses parity from an INI config string ("N", "E", "O").
    /// Use `SerialParity(string:)` at the call site when parsing config files.
    public convenience init(name:          String,
                            port:          String,
                            speed:         Int    = 9600,
                            dataBits:      Int    = 8,
                            parityString:  String,
                            stopBits:      Int    = 1,
                            preamble:    Int  = 350,
                            txtail:      Int  = 20,
                            persistence: Int  = 64,
                            slottime:    Int  = 20,
                            flowControl: Bool = false,
                            beaconInterval: TimeInterval? = nil,
                            beaconData:     String        = "",
                            transport: SerialPortTransport) {
        self.init(name: name, port: port,
                  speed: speed, dataBits: dataBits,
                  parity: SerialParity(string: parityString), stopBits: stopBits,
                  preamble: preamble, txtail: txtail,
                  persistence: persistence, slottime: slottime,
                  flowControl: flowControl,
                  beaconInterval: beaconInterval, beaconData: beaconData,
                  transport: transport)
    }

    // MARK: - Interface lifecycle

    /// Open the serial port, configure the KISS TNC, and bring the interface online.
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

    /// Take the interface offline and close the serial port.
    public func stop() {
        lock.lock()
        isOnline       = false
        interfaceReady = false
        lock.unlock()
        transport.close()
    }

    // MARK: - KISS TNC configuration commands

    /// Send all KISS configuration commands to the TNC.
    private func sendKISSConfig() {
        setPreamble(preamble)
        setTxTail(txtail)
        setPersistence(persistence)
        setSlotTime(slottime)
        setFlowControl(flowControl)
    }

    /// Python: `setPreamble(preamble)` — `FEND CMD_TXDELAY value FEND`
    public func setPreamble(_ preamble: Int) {
        var value = preamble / 10
        value = max(0, min(255, value))
        let cmd = Data([KISS.fend, KISS.cmdTxDelay, UInt8(value), KISS.fend])
        try? transport.write(cmd)
    }

    /// Python: `setTxTail(txtail)` — `FEND CMD_TXTAIL value FEND`
    public func setTxTail(_ txtail: Int) {
        var value = txtail / 10
        value = max(0, min(255, value))
        let cmd = Data([KISS.fend, KISS.cmdTxTail, UInt8(value), KISS.fend])
        try? transport.write(cmd)
    }

    /// Python: `setPersistence(persistence)` — `FEND CMD_P value FEND`
    public func setPersistence(_ persistence: Int) {
        let value = UInt8(max(0, min(255, persistence)))
        let cmd = Data([KISS.fend, KISS.cmdP, value, KISS.fend])
        try? transport.write(cmd)
    }

    /// Python: `setSlotTime(slottime)` — `FEND CMD_SLOTTIME value FEND`
    public func setSlotTime(_ slottime: Int) {
        var value = slottime / 10
        value = max(0, min(255, value))
        let cmd = Data([KISS.fend, KISS.cmdSlotTime, UInt8(value), KISS.fend])
        try? transport.write(cmd)
    }

    /// Python: `setFlowControl(_)` — `FEND CMD_READY 0x01 FEND`
    public func setFlowControl(_ enabled: Bool) {
        let cmd = Data([KISS.fend, KISS.cmdReady, 0x01, KISS.fend])
        try? transport.write(cmd)
    }

    // MARK: - Outgoing

    /// Send a Reticulum packet.  Called by Transport.
    ///
    /// Applies the IFAC mask (when an IFAC key is configured) before KISS
    /// framing, mirroring the central IFAC application in Python
    /// `Transport.transmit`. Without this, frames go out un-masked and
    /// IFAC-protected Python peers drop them.
    public func send(_ packet: Packet) throws {
        guard let raw = try? packet.pack() else { return }
        processOutgoing(wrapIfac(raw))
    }

    /// KISS-frame `data` and write to the TNC (or queue when not ready).
    ///
    /// Python: `process_outgoing(data)`
    public func processOutgoing(_ data: Data) {
        // Decide send-vs-enqueue atomically under `lock`: `interfaceReady` and
        // `packetQueue` are two halves of the same flow-control state, so the
        // read of `interfaceReady` and the enqueue must be one critical section
        // (otherwise the CMD_READY handler racing here loses packets or double-sends).
        lock.lock()
        guard isOnline else { lock.unlock(); return }
        if interfaceReady {
            if flowControl {
                interfaceReady = false
            }
            lock.unlock()
            let framed = KISS.frame(data)
            try? transport.write(framed)
            counters.addTx(bytes: data.count)   // Python counts original (unframed) bytes
        } else {
            packetQueue.append(data)
            lock.unlock()
        }
    }

    /// Pop and send the first queued packet; mark TNC as ready.
    ///
    /// Python: `process_queue()`
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
    /// KISS frames are decoded; `CMD_DATA` frames are delivered to the inbound
    /// handler; `CMD_READY` events trigger the outbound queue.
    public func feedBytes(_ data: Data) {
        let frames = decoder.feed(data)
        for (cmd, payload) in frames {
            if cmd == KISS.cmdData {
                counters.addRx(bytes: payload.count)
                rawInboundHandler?(payload, self)
            } else if cmd == KISS.cmdReady {
                processQueue()
            }
        }
    }

    // MARK: - Queue inspection (for tests)

    /// Number of packets currently queued (waiting for CMD_READY).
    public var queuedPacketCount: Int {
        lock.lock(); defer { lock.unlock() }
        return packetQueue.count
    }
}
