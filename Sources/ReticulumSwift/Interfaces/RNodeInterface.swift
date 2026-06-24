import Foundation

// MARK: - KISS framing + full command set
// All CMD_* constants match the Python KISS class in RNodeInterface.py exactly.

public enum KISS {
    // ── Framing ──────────────────────────────────────────────────────────────
    public static let fend:  UInt8 = 0xC0
    public static let fesc:  UInt8 = 0xDB
    public static let tfend: UInt8 = 0xDC
    public static let tfesc: UInt8 = 0xDD

    // ── Data / command bytes ──────────────────────────────────────────────────
    /// Alias for backward compat with older callers that used `commandData`
    public static var commandData: UInt8 { cmdData }

    public static let cmdData:        UInt8 = 0x00
    public static let cmdFrequency:   UInt8 = 0x01
    public static let cmdBandwidth:   UInt8 = 0x02
    public static let cmdTxpower:     UInt8 = 0x03
    public static let cmdSf:          UInt8 = 0x04
    public static let cmdCr:          UInt8 = 0x05
    public static let cmdRadioState:  UInt8 = 0x06
    public static let cmdRadioLock:   UInt8 = 0x07
    public static let cmdDetect:      UInt8 = 0x08
    public static let cmdLeave:       UInt8 = 0x0A
    public static let cmdStAlock:     UInt8 = 0x0B
    public static let cmdLtAlock:     UInt8 = 0x0C
    public static let cmdReady:       UInt8 = 0x0F
    public static let cmdStatRx:      UInt8 = 0x21
    public static let cmdStatTx:      UInt8 = 0x22
    public static let cmdStatRssi:    UInt8 = 0x23
    public static let cmdStatSnr:     UInt8 = 0x24
    public static let cmdStatChtm:    UInt8 = 0x25
    public static let cmdStatPhyprm:  UInt8 = 0x26
    public static let cmdStatBat:     UInt8 = 0x27
    public static let cmdStatCsma:    UInt8 = 0x28
    public static let cmdStatTemp:    UInt8 = 0x29
    public static let cmdBlink:       UInt8 = 0x30
    public static let cmdRandom:      UInt8 = 0x40
    public static let cmdFbExt:       UInt8 = 0x41
    public static let cmdFbRead:      UInt8 = 0x42
    public static let cmdFbWrite:     UInt8 = 0x43
    public static let cmdBtCtrl:      UInt8 = 0x46
    public static let cmdDispRead:    UInt8 = 0x66
    public static let cmdPlatform:    UInt8 = 0x48
    public static let cmdMcu:         UInt8 = 0x49
    public static let cmdFwVersion:   UInt8 = 0x50
    public static let cmdRomRead:     UInt8 = 0x51
    public static let cmdReset:       UInt8 = 0x55
    public static let cmdError:       UInt8 = 0x90
    public static let cmdUnknown:     UInt8 = 0xFE

    // MARK: – KISS TNC protocol aliases (KISSInterface / AX25KISSInterface)
    // 0x01–0x06 overlap with RNode radio cmd bytes; semantics differ per interface type.
    public static let cmdTxDelay:     UInt8 = 0x01   // == cmdFrequency in RNode context
    public static let cmdP:           UInt8 = 0x02   // == cmdBandwidth in RNode context
    public static let cmdSlotTime:    UInt8 = 0x03   // == cmdTxpower in RNode context
    public static let cmdTxTail:      UInt8 = 0x04   // == cmdSf in RNode context
    public static let cmdFullDuplex:  UInt8 = 0x05   // == cmdCr in RNode context
    public static let cmdSetHardware: UInt8 = 0x06   // == cmdRadioState in RNode context
    public static let cmdReturn:      UInt8 = 0xFF

    // ── Multi-interface specific ──────────────────────────────────────────────
    /// CMD_SEL_INT: selects the active sub-interface for subsequent config commands
    public static let cmdSelInt:      UInt8 = 0x1F
    /// CMD_INTERFACES: detect response lists hardware interface types
    public static let cmdInterfaces:  UInt8 = 0x71

    /// Incoming data command bytes — one per sub-interface channel
    /// (command byte in KISS frame that carries data FROM a specific channel)
    public static let cmdInt0Data:  UInt8 = 0x00   // same as cmdData — channel 0
    public static let cmdInt1Data:  UInt8 = 0x10
    public static let cmdInt2Data:  UInt8 = 0x20
    public static let cmdInt3Data:  UInt8 = 0x70
    public static let cmdInt4Data:  UInt8 = 0x75
    public static let cmdInt5Data:  UInt8 = 0x90
    public static let cmdInt6Data:  UInt8 = 0xA0
    public static let cmdInt7Data:  UInt8 = 0xB0
    public static let cmdInt8Data:  UInt8 = 0xC0
    public static let cmdInt9Data:  UInt8 = 0xD0
    public static let cmdInt10Data: UInt8 = 0xE0
    public static let cmdInt11Data: UInt8 = 0xF0

    /// Mapping from cmdIntNData values to sub-interface index (0-based)
    public static let intDataCommands: [UInt8] = [
        0x00, 0x10, 0x20, 0x70, 0x75, 0x90, 0xA0, 0xB0, 0xC0, 0xD0, 0xE0, 0xF0
    ]

    // ── Interface chip type identifiers ───────────────────────────────────────
    public static let sx127x: UInt8 = 0x00
    public static let sx1276: UInt8 = 0x01
    public static let sx1278: UInt8 = 0x02
    public static let sx126x: UInt8 = 0x10
    public static let sx1262: UInt8 = 0x11
    public static let sx128x: UInt8 = 0x20
    public static let sx1280: UInt8 = 0x21

    /// Python: KISS.interface_type_to_str()
    public static func interfaceTypeToString(_ type: UInt8) -> String {
        switch type {
        case sx126x, sx1262:           return "SX126X"
        case sx127x, sx1276, sx1278:   return "SX127X"
        case sx128x, sx1280:           return "SX128X"
        default:                       return "SX127X"
        }
    }

    // ── Detect handshake ─────────────────────────────────────────────────────
    public static let detectReq:      UInt8 = 0x73
    public static let detectResp:     UInt8 = 0x46

    // ── Radio state values ────────────────────────────────────────────────────
    public static let radioStateOff:  UInt8 = 0x00
    public static let radioStateOn:   UInt8 = 0x01
    public static let radioStateAsk:  UInt8 = 0xFF

    // ── Error codes ───────────────────────────────────────────────────────────
    public static let errorInitRadio:    UInt8 = 0x01
    public static let errorTxFailed:     UInt8 = 0x02
    public static let errorEepromLocked: UInt8 = 0x03
    public static let errorQueueFull:    UInt8 = 0x04
    public static let errorMemoryLow:    UInt8 = 0x05
    public static let errorModemTimeout: UInt8 = 0x06

    // ── Platform identifiers ──────────────────────────────────────────────────
    public static let platformAVR:   UInt8 = 0x90
    public static let platformESP32: UInt8 = 0x80
    public static let platformNRF52: UInt8 = 0x70

    // MARK: – KISS escape / frame helpers

    public static func escape(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count)
        for byte in data {
            switch byte {
            case fend: out.append(fesc); out.append(tfend)
            case fesc: out.append(fesc); out.append(tfesc)
            default:   out.append(byte)
            }
        }
        return out
    }

    public static func frameData(_ payload: Data, command: UInt8 = cmdData) -> Data {
        var out = Data()
        out.append(fend)
        out.append(command)
        out.append(escape(payload))
        out.append(fend)
        return out
    }

    /// Convenience alias used by KISSInterface / AX25KISSInterface.
    /// Equivalent to `frameData(data)` with `CMD_DATA`.
    public static func frame(_ data: Data) -> Data { frameData(data) }

    // MARK: – Frame decoder

    /// Stateful KISS frame decoder.
    ///
    /// Feed raw bytes as they arrive; receive `(command, payload)` pairs as
    /// frames complete.  The command byte is the first byte inside each frame
    /// (after the opening FEND); the payload is everything that follows.
    ///
    /// Used by `RNodeInterface`, `RNodeMultiInterface`, `KISSInterface`, and
    /// `AX25KISSInterface`.
    public final class FrameDecoder {
        private var inFrame       = false
        private var pendingEscape = false
        private var buffer        = Data()

        public init() {}

        /// Returns decoded `(command, payload)` pairs for each complete frame.
        public func feed(_ bytes: Data) -> [(command: UInt8, data: Data)] {
            var frames: [(UInt8, Data)] = []
            for byte in bytes {
                if byte == fend {
                    if inFrame && !buffer.isEmpty {
                        let cmd     = buffer[buffer.startIndex]
                        let payload = buffer.count > 1
                            ? Data(buffer[buffer.index(after: buffer.startIndex)...])
                            : Data()
                        frames.append((cmd, payload))
                    }
                    buffer.removeAll(keepingCapacity: true)
                    inFrame       = true
                    pendingEscape = false
                } else if !inFrame {
                    continue
                } else if byte == fesc {
                    pendingEscape = true
                } else if pendingEscape {
                    if byte == tfend      { buffer.append(fend) }
                    else if byte == tfesc { buffer.append(fesc) }
                    else                  { buffer.append(byte) }
                    pendingEscape = false
                } else {
                    buffer.append(byte)
                }
            }
            return frames
        }

        public func reset() {
            inFrame = false; pendingEscape = false; buffer = Data()
        }
    }
}

// MARK: - RNodeInterface

/// KISS-framed interface to an RNode LoRa modem.  The byte-stream backing
/// it (USB-serial, CoreBluetooth Nordic UART, TCP, etc.) is supplied by the
/// host application as an `RNodeTransport`. This file owns KISS framing and
/// the full RNode configuration / telemetry command set.
public final class RNodeInterface: Interface {

    // MARK: – Class constants (Python: RNodeInterface.XXXX)

    public static let hwMtuValue:       Int    = 508
    public static let freqMin:          UInt32 = 137_000_000
    public static let freqMax:          UInt32 = 3_000_000_000
    public static let rssiOffset:       Int    = 157
    public static let callsignMaxLen:   Int    = 32
    public static let requiredFwVerMaj: UInt8  = 1
    public static let requiredFwVerMin: UInt8  = 52
    public static let reconnectWait:    Int    = 5
    public static let qSnrMinBase:      Int    = -9
    public static let qSnrMax:          Int    = 6
    public static let qSnrStep:         Int    = 2

    public static let batteryStateUnknown:     UInt8 = 0x00
    public static let batteryStateDischarging: UInt8 = 0x01
    public static let batteryStateCharging:    UInt8 = 0x02
    public static let batteryStateCharged:     UInt8 = 0x03

    // MARK: – Interface protocol

    public let name:   String
    public var hwMtu:  Int?    { Self.hwMtuValue }
    public private(set) var bitrate: Int = 0

    public var isOnline: Bool = false

    public var inboundHandler:    ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data,   any Interface) -> Void)?
    public var ifacIdentity: Identity?
    public var ifacKey:      Data?
    public var ifacSize:     Int = Constants.defaultIfacSize

    // MARK: – Transport

    public weak var transport: RNodeTransport?
    private let decoder = KISS.FrameDecoder()

    // MARK: – Configured radio parameters (what we want)

    public var frequency:  UInt32 = 0
    public var bandwidth:  UInt32 = 0
    public var txPower:    Int    = 0
    public var sf:         Int    = 0   // spreading factor
    public var cr:         Int    = 0   // coding rate
    public var state:      UInt8  = KISS.radioStateOff
    public var stAlock:    Double? = nil
    public var ltAlock:    Double? = nil

    // MARK: – Reported (echoed) radio parameters (what the device says it has)

    public var rFrequency: UInt32? = nil
    public var rBandwidth: UInt32? = nil
    public var rTxPower:   Int?    = nil
    public var rSf:        Int?    = nil
    public var rCr:        Int?    = nil
    public var rState:     UInt8?  = nil
    public var rLock:      UInt8?  = nil
    public var rStAlock:   Double? = nil
    public var rLtAlock:   Double? = nil

    // MARK: – Firmware / hardware info

    public var majVersion:  UInt8 = 0
    public var minVersion:  UInt8 = 0
    public var firmwareOk:  Bool  = false
    public var detected:    Bool  = false
    public var platform:    UInt8? = nil
    public var mcu:         UInt8? = nil
    public var hwErrors:    [UInt8] = []

    // MARK: – Telemetry

    public var rStatRx:    UInt32? = nil
    public var rStatTx:    UInt32? = nil
    public var rStatRssi:  Int?    = nil
    public var rStatSnr:   Float?  = nil
    public var rStatQ:     Double? = nil
    public var rRandom:    UInt8?  = nil

    public var rAirtimeShort:      Double = 0.0
    public var rAirtimeLong:       Double = 0.0
    public var rChannelLoadShort:  Double = 0.0
    public var rChannelLoadLong:   Double = 0.0
    public var rCurrentRssi:       Int?   = nil
    public var rNoiseFloor:        Int?   = nil
    public var rInterference:      Int?   = nil

    public var rSymbolTimeMs:    Double? = nil
    public var rSymbolRate:      Int?    = nil
    public var rPreambleSymbols: Int?    = nil
    public var rPreambleTimeMs:  Int?    = nil
    public var rCsmaSlotTimeMs:  Int?    = nil
    public var rCsmaDifsMs:      Int?    = nil
    public var rCsmaCwBand:      UInt8?  = nil
    public var rCsmaCwMin:       UInt8?  = nil
    public var rCsmaCwMax:       UInt8?  = nil

    public var rBatteryState:   UInt8 = RNodeInterface.batteryStateUnknown
    public var rBatteryPercent: UInt8 = 0
    public var rTemperature:    Int?  = nil

    // MARK: – Flow control / TX queue

    public var interfaceReady: Bool  = true
    public var flowControl:    Bool  = false
    public var packetQueue:    [Data] = []

    // MARK: – Init

    public init(name: String, transport: RNodeTransport, bitrate: Int = 0) {
        self.name      = name
        self.transport = transport
        self.bitrate   = bitrate
        transport.byteHandler = { [weak self] data in self?.handleIncoming(data) }
    }

    // MARK: – Interface lifecycle

    public func start() throws {
        try transport?.open()
        isOnline = true
    }

    public func stop() {
        transport?.close()
        isOnline = false
    }

    public func send(_ packet: Packet) throws {
        guard let transport, isOnline else { return }
        let raw = try packet.pack()
        try transport.write(KISS.frameData(wrapIfac(raw)))
    }

    // MARK: – Incoming byte handler

    private func handleIncoming(_ data: Data) {
        let frames = decoder.feed(data)
        for (cmd, payload) in frames {
            if cmd == KISS.cmdData {
                dispatchInboundData(payload)
            } else {
                processCommandFrame(cmd: cmd, payload: payload)
            }
        }
    }

    private func dispatchInboundData(_ payload: Data) {
        if let h = rawInboundHandler {
            h(payload, self)
        } else if let packet = try? Packet.unpack(payload) {
            inboundHandler?(packet, self)
        }
    }

    // MARK: – Command frame dispatcher (Python: readLoop elif chain)

    private func processCommandFrame(cmd: UInt8, payload: Data) {
        switch cmd {

        case KISS.cmdFrequency:
            if payload.count >= 4 {
                rFrequency = uint32BigEndian(payload)
                updateBitrate()
            }

        case KISS.cmdBandwidth:
            if payload.count >= 4 {
                rBandwidth = uint32BigEndian(payload)
                updateBitrate()
            }

        case KISS.cmdTxpower:
            if let b = payload.first { rTxPower = Int(b) }

        case KISS.cmdSf:
            if let b = payload.first { rSf = Int(b); updateBitrate() }

        case KISS.cmdCr:
            if let b = payload.first { rCr = Int(b); updateBitrate() }

        case KISS.cmdRadioState:
            if let b = payload.first { rState = b }

        case KISS.cmdRadioLock:
            if let b = payload.first { rLock = b }

        case KISS.cmdDetect:
            if let b = payload.first { detected = (b == KISS.detectResp) }

        case KISS.cmdPlatform:
            if let b = payload.first { platform = b }

        case KISS.cmdMcu:
            if let b = payload.first { mcu = b }

        case KISS.cmdFwVersion:
            if payload.count >= 2 {
                majVersion = payload[payload.startIndex]
                minVersion = payload[payload.startIndex + 1]
                validateFirmware()
            }

        case KISS.cmdStatRx:
            if payload.count >= 4 { rStatRx = uint32BigEndian(payload) }

        case KISS.cmdStatTx:
            if payload.count >= 4 { rStatTx = uint32BigEndian(payload) }

        case KISS.cmdStatRssi:
            if let b = payload.first {
                rStatRssi = Int(b) - RNodeInterface.rssiOffset
            }

        case KISS.cmdStatSnr:
            if let b = payload.first {
                let signed = Int8(bitPattern: b)
                let snr = Float(signed) * 0.25
                rStatSnr = snr
                computeSnrQuality(snr: snr)
            }

        case KISS.cmdStatBat:
            if payload.count >= 2 {
                rBatteryState = payload[payload.startIndex]
                var pct = Int(payload[payload.startIndex + 1])
                if pct > 100 { pct = 100 }
                if pct < 0   { pct = 0   }
                rBatteryPercent = UInt8(pct)
            }

        case KISS.cmdStatTemp:
            if let b = payload.first {
                let temp = Int(b) - 120
                if temp >= -30 && temp <= 90 { rTemperature = temp }
                else                         { rTemperature = nil  }
            }

        case KISS.cmdRandom:
            if let b = payload.first { rRandom = b }

        case KISS.cmdStAlock:
            if payload.count >= 2 {
                let at = (Int(payload[payload.startIndex]) << 8) | Int(payload[payload.startIndex + 1])
                rStAlock = Double(at) / 100.0
            }

        case KISS.cmdLtAlock:
            if payload.count >= 2 {
                let at = (Int(payload[payload.startIndex]) << 8) | Int(payload[payload.startIndex + 1])
                rLtAlock = Double(at) / 100.0
            }

        case KISS.cmdStatChtm:
            processChannelTiming(payload)

        case KISS.cmdStatPhyprm:
            processPhyParams(payload)

        case KISS.cmdStatCsma:
            if payload.count >= 3 {
                rCsmaCwBand = payload[payload.startIndex]
                rCsmaCwMin  = payload[payload.startIndex + 1]
                rCsmaCwMax  = payload[payload.startIndex + 2]
            }

        case KISS.cmdError:
            if let b = payload.first { handleError(b) }

        case KISS.cmdReady:
            interfaceReady = true
            try? processQueue()

        default:
            break
        }
    }

    // MARK: – SNR quality

    private func computeSnrQuality(snr: Float) {
        guard let sf = rSf else { return }
        let sfs = sf - 7
        let qSnrMin = RNodeInterface.qSnrMinBase - sfs * RNodeInterface.qSnrStep
        let qSnrMax = RNodeInterface.qSnrMax
        let span    = qSnrMax - qSnrMin
        guard span > 0 else { rStatQ = 0.0; return }
        var quality = (Double(snr) - Double(qSnrMin)) / Double(span) * 100.0
        quality = max(0.0, min(100.0, quality))
        rStatQ = round(quality * 10.0) / 10.0
    }

    // MARK: – Channel timing (CMD_STAT_CHTM, 11 bytes)

    private func processChannelTiming(_ payload: Data) {
        guard payload.count >= 11 else { return }
        let p = payload
        let i = p.startIndex
        let ats = (Int(p[i+0]) << 8) | Int(p[i+1])
        let atl = (Int(p[i+2]) << 8) | Int(p[i+3])
        let cus = (Int(p[i+4]) << 8) | Int(p[i+5])
        let cul = (Int(p[i+6]) << 8) | Int(p[i+7])
        let crs = p[i+8]
        let nfl = p[i+9]
        let ntf = p[i+10]

        rAirtimeShort      = Double(ats) / 100.0
        rAirtimeLong       = Double(atl) / 100.0
        rChannelLoadShort  = Double(cus) / 100.0
        rChannelLoadLong   = Double(cul) / 100.0
        rCurrentRssi       = Int(crs) - RNodeInterface.rssiOffset
        rNoiseFloor        = Int(nfl) - RNodeInterface.rssiOffset
        if ntf == 0xFF {
            rInterference = nil
        } else {
            rInterference = Int(ntf) - RNodeInterface.rssiOffset
        }
    }

    // MARK: – PHY parameters (CMD_STAT_PHYPRM, 12 bytes)

    private func processPhyParams(_ payload: Data) {
        guard payload.count >= 12 else { return }
        let p = payload
        let i = p.startIndex
        let lst = (Int(p[i+0])  << 8) | Int(p[i+1])   // symbol time * 1000
        let lsr = (Int(p[i+2])  << 8) | Int(p[i+3])
        let prs = (Int(p[i+4])  << 8) | Int(p[i+5])
        let prt = (Int(p[i+6])  << 8) | Int(p[i+7])
        let cst = (Int(p[i+8])  << 8) | Int(p[i+9])
        let dft = (Int(p[i+10]) << 8) | Int(p[i+11])
        rSymbolTimeMs    = Double(lst) / 1000.0
        rSymbolRate      = lsr
        rPreambleSymbols = prs
        rPreambleTimeMs  = prt
        rCsmaSlotTimeMs  = cst
        rCsmaDifsMs      = dft
    }

    // MARK: – Error handling

    private func handleError(_ code: UInt8) {
        switch code {
        case KISS.errorMemoryLow:
            hwErrors.append(code)
        case KISS.errorModemTimeout:
            hwErrors.append(code)
        default:
            hwErrors.append(code)
        }
    }

    // MARK: – Bitrate computation (Python: updateBitrate)

    public func updateBitrate() {
        guard let sf = rSf, let bw = rBandwidth, let cr = rCr,
              sf > 0, bw > 0, cr > 0 else {
            bitrate = 0
            return
        }
        let bwKhz = Double(bw) / 1000.0
        let sf2   = pow(2.0, Double(sf))
        let crRat = 4.0 / Double(cr)
        bitrate = Int(Double(sf) * (crRat / (sf2 / bwKhz)) * 1000.0)
    }

    // MARK: – Radio configuration commands

    /// Python: detect() — sends 4 KISS frames asking for detect / fw / platform / mcu
    public func detect() throws {
        // Exact byte sequence from Python:
        // [FEND CMD_DETECT DETECT_REQ FEND CMD_FW_VERSION 0x00
        //  FEND CMD_PLATFORM 0x00 FEND CMD_MCU 0x00 FEND]
        let cmd = Data([
            KISS.fend, KISS.cmdDetect,    KISS.detectReq,
            KISS.fend, KISS.cmdFwVersion, 0x00,
            KISS.fend, KISS.cmdPlatform,  0x00,
            KISS.fend, KISS.cmdMcu,       0x00,
            KISS.fend
        ])
        try transport?.write(cmd)
    }

    /// Python: leave() → [FEND CMD_LEAVE 0xFF FEND]
    public func leave() throws {
        try transport?.write(Data([KISS.fend, KISS.cmdLeave, 0xFF, KISS.fend]))
    }

    /// Python: hard_reset() → [FEND CMD_RESET 0xF8 FEND]
    public func hardReset() throws {
        try transport?.write(Data([KISS.fend, KISS.cmdReset, 0xF8, KISS.fend]))
    }

    /// Python: setFrequency() — 4-byte big-endian uint32, KISS-escaped
    public func setFrequency() throws {
        let data = uint32ToData(frequency)
        try sendCommand(KISS.cmdFrequency, data: data)
    }

    /// Python: setBandwidth() — 4-byte big-endian uint32, KISS-escaped
    public func setBandwidth() throws {
        let data = uint32ToData(bandwidth)
        try sendCommand(KISS.cmdBandwidth, data: data)
    }

    /// Python: setTXPower() — single byte
    public func setTxPower() throws {
        try sendCommand(KISS.cmdTxpower, data: Data([UInt8(clamping: txPower)]))
    }

    /// Python: setSpreadingFactor() — single byte
    public func setSpreadingFactor() throws {
        try sendCommand(KISS.cmdSf, data: Data([UInt8(clamping: sf)]))
    }

    /// Python: setCodingRate() — single byte
    public func setCodingRate() throws {
        try sendCommand(KISS.cmdCr, data: Data([UInt8(clamping: cr)]))
    }

    /// Python: setSTALock — 2-byte big-endian (int(alock*100))
    public func setStAlock() throws {
        guard let at = stAlock else { return }
        let v = Int(at * 100)
        let data = Data([UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
        try sendCommand(KISS.cmdStAlock, data: data)
    }

    /// Python: setLTALock — 2-byte big-endian (int(alock*100))
    public func setLtAlock() throws {
        guard let at = ltAlock else { return }
        let v = Int(at * 100)
        let data = Data([UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
        try sendCommand(KISS.cmdLtAlock, data: data)
    }

    /// Python: setRadioState()
    public func setRadioState(_ s: UInt8) throws {
        state = s
        try sendCommand(KISS.cmdRadioState, data: Data([s]))
    }

    /// Python: initRadio() — sends all config in order, then radio ON
    public func initRadio() throws {
        try setFrequency()
        try setBandwidth()
        try setTxPower()
        try setSpreadingFactor()
        try setCodingRate()
        try setStAlock()
        try setLtAlock()
        try setRadioState(KISS.radioStateOn)
    }

    // MARK: – Firmware validation (Python: validate_firmware)

    public func validateFirmware() {
        if majVersion > RNodeInterface.requiredFwVerMaj {
            firmwareOk = true
            return
        }
        if majVersion == RNodeInterface.requiredFwVerMaj &&
           minVersion >= RNodeInterface.requiredFwVerMin {
            firmwareOk = true
            return
        }
        firmwareOk = false
    }

    // MARK: – Radio state validation (Python: validateRadioState)

    public func validateRadioState() -> Bool {
        var valid = true
        if let rf = rFrequency, abs(Int(frequency) - Int(rf)) > 100 { valid = false }
        if let rb = rBandwidth, bandwidth != rb                       { valid = false }
        if let rt = rTxPower,  txPower   != rt                       { valid = false }
        if let rs = rSf,       sf        != rs                        { valid = false }
        if let st = rState,    state     != st                        { valid = false }
        return valid
    }

    // MARK: – Radio state reset (Python: reset_radio_state)

    public func resetRadioState() {
        rFrequency = nil
        rBandwidth = nil
        rTxPower   = nil
        rSf        = nil
        rCr        = nil
        rState     = nil
        rLock      = nil
        detected   = false
    }

    // MARK: – TX queue (Python: queue / process_queue)

    public func queue(_ data: Data) {
        packetQueue.append(data)
    }

    public func processQueue() throws {
        if packetQueue.isEmpty {
            interfaceReady = true
        } else {
            let data = packetQueue.removeFirst()
            interfaceReady = true
            // Wrap as KISS data frame and write
            try transport?.write(KISS.frameData(data))
        }
    }

    // MARK: – Battery accessors (Python: get_battery_state / get_battery_percent)

    public func getBatteryState() -> UInt8 { rBatteryState }
    public func getBatteryPercent() -> UInt8 { rBatteryPercent }

    public func getBatteryStateString() -> String {
        switch rBatteryState {
        case RNodeInterface.batteryStateCharged:     return "charged"
        case RNodeInterface.batteryStateCharging:    return "charging"
        case RNodeInterface.batteryStateDischarging: return "discharging"
        default:                                      return "unknown"
        }
    }

    // MARK: – Private helpers

    /// Build a KISS command frame: FEND + cmd + escape(data) + FEND
    private func sendCommand(_ cmd: UInt8, data: Data) throws {
        var frame = Data()
        frame.append(KISS.fend)
        frame.append(cmd)
        frame.append(KISS.escape(data))
        frame.append(KISS.fend)
        try transport?.write(frame)
    }

    /// Pack a UInt32 as 4-byte big-endian Data
    private func uint32ToData(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >>  8) & 0xFF),
            UInt8( value        & 0xFF)
        ])
    }

    /// Read 4 bytes from Data as big-endian UInt32
    private func uint32BigEndian(_ data: Data) -> UInt32 {
        let i = data.startIndex
        return (UInt32(data[i]) << 24) |
               (UInt32(data[i+1]) << 16) |
               (UInt32(data[i+2]) << 8)  |
                UInt32(data[i+3])
    }
}

// MARK: - RNodeTransport protocol

/// Adapter the host implements to bridge a real serial-style transport
/// (USB serial, BLE NUS, TCP) into the RNode interface.
public protocol RNodeTransport: AnyObject {
    var byteHandler: ((Data) -> Void)? { get set }
    func open()  throws
    func close()
    func write(_ data: Data) throws
}
