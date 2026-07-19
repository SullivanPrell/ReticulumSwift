import Foundation

// MARK: - RNodeSubInterface

/// Per-channel radio configuration for one physical radio channel on a multi-interface RNode.
/// Corresponds to Python `RNodeSubInterface`.
///
/// This is a class (not a struct) so it can conform to `Interface` (which requires `AnyObject`)
/// and be passed directly as `any Interface` to inbound handlers, enabling callers to downcast
/// back to `RNodeSubInterface` for channel identification.
public final class RNodeSubInterface: Interface {

    // MARK: – Identity

    public let name:          String
    public let index:         Int           // vport index (0-based)
    public let interfaceType: String        // "SX127X", "SX126X", or "SX128X"

    // MARK: – Desired radio parameters (what we want)

    public let frequency: UInt32
    public let bandwidth: UInt32
    public let txPower:   Int
    public let sf:        Int
    public let cr:        Int
    public var flowControl: Bool   = false
    public var stAlock:   Double?  = nil
    public var ltAlock:   Double?  = nil

    // MARK: – Reported (echoed) parameters (what the hardware says it set)

    public var rFrequency: UInt32? = nil
    public var rBandwidth: UInt32? = nil
    public var rTxPower:   Int?    = nil
    public var rSf:        Int?    = nil
    public var rCr:        Int?    = nil
    public var rState:     UInt8?  = nil
    public var rLock:      UInt8?  = nil
    public var rStAlock:   Double? = nil
    public var rLtAlock:   Double? = nil

    // MARK: – State

    public var state: UInt8 = KISS.radioStateOff

    // MARK: – Telemetry

    public var rStatRssi:  Int?   = nil
    public var rStatSnr:   Float? = nil
    public var rStatQ:     Double? = nil
    public var rRandom:    UInt8?  = nil

    public var rSymbolTimeMs:    Double? = nil
    public var rSymbolRate:      Int?    = nil
    public var rPreambleSymbols: Int?    = nil
    public var rPreambleTimeMs:  Int?    = nil
    public var rCsmaSlotTimeMs:  Int?    = nil

    // MARK: – Statistics (override Interface default extensions that return 0)

    /// Total bytes received on this sub-channel
    public var rxBytes: Int = 0
    /// Total bytes transmitted on this sub-channel
    public var txBytes: Int = 0

    // MARK: – Interface protocol requirements

    /// Always online once added to a multi-interface (online management is the parent's job).
    public var isOnline:  Bool   = true
    public var bitrate:   Int    = 0

    public var inboundHandler:    ((Packet, any Interface) -> Void)? = nil
    /// Raw inbound handler — not used on sub-interfaces (parent multi handles raw delivery).
    public var rawInboundHandler: ((Data,   any Interface) -> Void)? = nil
    public var ifacIdentity: Identity? = nil
    public var ifacKey:      Data?     = nil
    public var ifacSize:     Int       = Constants.defaultIfacSize

    /// Sends are routed through the parent `RNodeMultiInterface`.
    /// Direct calls on a sub-interface are no-ops; use the parent's `processOutgoing`.
    public func send(_ packet: Packet) throws { }
    public func start() throws { }
    public func stop() { }

    // MARK: – Init

    public init(
        name:          String,
        index:         Int,
        interfaceType: String,
        frequency:     UInt32,
        bandwidth:     UInt32,
        txPower:       Int,
        sf:            Int,
        cr:            Int,
        flowControl:   Bool    = false,
        stAlock:       Double? = nil,
        ltAlock:       Double? = nil
    ) {
        self.name          = name
        self.index         = index
        self.interfaceType = interfaceType
        self.frequency     = frequency
        self.bandwidth     = bandwidth
        self.txPower       = txPower
        self.sf            = sf
        self.cr            = cr
        self.flowControl   = flowControl
        self.stAlock       = stAlock
        self.ltAlock       = ltAlock
    }

    // MARK: – Description (Python: __str__)

    public var description: String { "RNodeSubInterface[\(name)]" }
}

// MARK: - RNodeMultiInterface

/// Multi-channel RNode interface that manages N sub-interfaces over a single physical transport.
/// Corresponds to Python `RNodeMultiInterface`.
///
/// Multiplexing scheme (from Python):
/// - **Outgoing**: Each packet is preceded by a `CMD_SEL_INT` frame that selects the sub-interface
///   by its vport index. Format: `[FEND CMD_SEL_INT index FEND FEND CMD_DATA escaped_payload FEND]`
/// - **Incoming data**: The command byte in the KISS frame indicates which channel the data is from.
///   `CMD_INT0_DATA(0x00)` = channel 0, `CMD_INT1_DATA(0x10)` = channel 1, etc.
///   Alternatively a `CMD_SEL_INT` frame updates `selectedIndex` and the next data frame is for
///   that channel.
/// - **Incoming telemetry**: `CMD_SEL_INT` updates `selectedIndex`; subsequent telemetry frames
///   (frequency, bandwidth, RSSI, SNR, etc.) are attributed to `subInterfaces[selectedIndex]`.
public final class RNodeMultiInterface: Interface {

    // MARK: – Class constants (Python: RNodeMultiInterface.XXXX)

    public static let maxSubInterfaces:   Int    = 11
    public static let hwMtuValue:         Int    = 508
    public static let requiredFwVerMaj:   UInt8  = 1
    public static let requiredFwVerMin:   UInt8  = 74
    public static let reconnectWait:      Int    = 5
    public static let callsignMaxLen:     Int    = 32
    public static let rssiOffset:         Int    = 157
    public static let qSnrMinBase:        Int    = -9
    public static let qSnrMax:            Int    = 6
    public static let qSnrStep:           Int    = 2

    // MARK: – Interface protocol

    public let name: String
    public var hwMtu: Int? { Self.hwMtuValue }
    public var bitrate: Int = 0

    public var isOnline: Bool = false

    public var inboundHandler:    ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data,   any Interface) -> Void)?
    public var ifacIdentity: Identity?
    public var ifacKey:      Data?
    public var ifacSize:     Int = Constants.defaultIfacSize

    // MARK: – Sub-interfaces

    /// All configured sub-interfaces, in order of their vport index.
    public private(set) var subInterfaces: [RNodeSubInterface]

    /// Currently selected sub-interface index (updated by CMD_SEL_INT frames from hardware)
    public private(set) var selectedIndex: Int = 0

    // MARK: – Transport & decoder

    public weak var transport: RNodeTransport?
    private let decoder = KISS.FrameDecoder()

    // MARK: – Hardware / firmware state (shared across all sub-interfaces)

    public var majVersion:  UInt8 = 0
    public var minVersion:  UInt8 = 0
    public var firmwareOk:  Bool  = false
    public var detected:    Bool  = false
    public var platform:    UInt8? = nil
    public var mcu:         UInt8? = nil

    /// Interface types reported by CMD_INTERFACES (from device detect response)
    public private(set) var subInterfaceTypes: [String] = []


    // MARK: – Errors

    public enum MultiInterfaceError: Error {
        case noSubInterfaces
        case tooManySubInterfaces(Int)
    }

    // MARK: – Init

    public init(
        name:          String,
        transport:     RNodeTransport,
        subInterfaces: [RNodeSubInterface]
    ) throws {
        guard !subInterfaces.isEmpty else { throw MultiInterfaceError.noSubInterfaces }
        guard subInterfaces.count <= Self.maxSubInterfaces else {
            throw MultiInterfaceError.tooManySubInterfaces(subInterfaces.count)
        }
        self.name          = name
        self.transport     = transport
        self.subInterfaces = subInterfaces
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
        // RNodeMultiInterface does not send directly — only via a specific sub-interface.
        // Callers must use processOutgoing(_:subInterface:).
    }

    // MARK: – Radio configuration commands (Python: setFrequency/setBandwidth/etc.)
    //
    // Every command frame is preceded by a CMD_SEL_INT frame that selects the target sub-interface.
    // Python: kiss_command = [FEND CMD_SEL_INT interface.index FEND FEND CMD_xxx data FEND]

    /// Python: setFrequency(frequency, interface)
    public func setFrequency(for sub: RNodeSubInterface) throws {
        let data = uint32ToData(sub.frequency)
        try sendConfigCommand(KISS.cmdFrequency, data: data, subInterface: sub)
    }

    /// Python: setBandwidth(bandwidth, interface)
    public func setBandwidth(for sub: RNodeSubInterface) throws {
        let data = uint32ToData(sub.bandwidth)
        try sendConfigCommand(KISS.cmdBandwidth, data: data, subInterface: sub)
    }

    /// Python: setTXPower(txpower, interface)
    public func setTxPower(for sub: RNodeSubInterface) throws {
        try sendConfigCommand(KISS.cmdTxpower, data: Data([UInt8(clamping: sub.txPower)]), subInterface: sub)
    }

    /// Python: setSpreadingFactor(sf, interface)
    public func setSpreadingFactor(for sub: RNodeSubInterface) throws {
        try sendConfigCommand(KISS.cmdSf, data: Data([UInt8(clamping: sub.sf)]), subInterface: sub)
    }

    /// Python: setCodingRate(cr, interface)
    public func setCodingRate(for sub: RNodeSubInterface) throws {
        try sendConfigCommand(KISS.cmdCr, data: Data([UInt8(clamping: sub.cr)]), subInterface: sub)
    }

    /// Python: setSTALock(st_alock, interface)
    public func setStAlock(for sub: RNodeSubInterface) throws {
        guard let at = sub.stAlock else { return }
        let v = Int(at * 100)
        let data = Data([UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
        try sendConfigCommand(KISS.cmdStAlock, data: data, subInterface: sub)
    }

    /// Python: setLTALock(lt_alock, interface)
    public func setLtAlock(for sub: RNodeSubInterface) throws {
        guard let at = sub.ltAlock else { return }
        let v = Int(at * 100)
        let data = Data([UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
        try sendConfigCommand(KISS.cmdLtAlock, data: data, subInterface: sub)
    }

    /// Python: setRadioState(state, interface)
    public func setRadioState(_ state: UInt8, for sub: RNodeSubInterface) throws {
        try sendConfigCommand(KISS.cmdRadioState, data: Data([state]), subInterface: sub)
    }

    // MARK: – initRadio per sub-interface (Python: RNodeSubInterface.initRadio)

    /// Configure one sub-interface: sends all parameters in order then turns radio ON.
    /// Mutates `sub.state` to `radioStateOn`.
    public func initRadio(for sub: inout RNodeSubInterface) throws {
        try setFrequency(for: sub)
        try setBandwidth(for: sub)
        try setTxPower(for: sub)
        try setSpreadingFactor(for: sub)
        try setCodingRate(for: sub)
        try setStAlock(for: sub)
        try setLtAlock(for: sub)
        try setRadioState(KISS.radioStateOn, for: sub)
        sub.state = KISS.radioStateOn
    }

    /// Configure all sub-interfaces.
    public func initAllRadios() throws {
        for i in subInterfaces.indices {
            try initRadio(for: &subInterfaces[i])
        }
    }

    // MARK: – Outgoing data (Python: process_outgoing(data, interface))

    /// Send `data` on the specified sub-interface's channel.
    /// Format: `[FEND CMD_SEL_INT index FEND FEND CMD_DATA escaped_data FEND]`
    /// If `subInterface` is nil, does nothing (matches Python behaviour for direct calls on parent).
    public func processOutgoing(_ data: Data, subInterface: RNodeSubInterface?) throws {
        guard let sub = subInterface else { return }
        let escaped = KISS.escape(data)
        var frame = Data()
        frame.append(KISS.fend)
        frame.append(KISS.cmdSelInt)
        frame.append(UInt8(sub.index))
        frame.append(KISS.fend)
        frame.append(KISS.fend)
        frame.append(KISS.cmdData)
        frame.append(escaped)
        frame.append(KISS.fend)
        try transport?.write(frame)
        // Track TX bytes (unescaped original length)
        subInterfaces[sub.index].txBytes += data.count
    }

    // MARK: – detect() (Python: detect())

    /// Python: detect() — sends 5 KISS frames asking for detect / fw / platform / mcu / interfaces
    public func detect() throws {
        let cmd = Data([
            KISS.fend, KISS.cmdDetect,     KISS.detectReq,
            KISS.fend, KISS.cmdFwVersion,  0x00,
            KISS.fend, KISS.cmdPlatform,   0x00,
            KISS.fend, KISS.cmdMcu,        0x00,
            KISS.fend, KISS.cmdInterfaces, 0x00,
            KISS.fend
        ])
        try transport?.write(cmd)
    }

    // MARK: – Firmware validation (Python: validate_firmware)

    public func validateFirmware() {
        if majVersion > Self.requiredFwVerMaj {
            firmwareOk = true
            return
        }
        if majVersion == Self.requiredFwVerMaj && minVersion >= Self.requiredFwVerMin {
            firmwareOk = true
            return
        }
        firmwareOk = false
    }

    // MARK: – Description (Python: __str__)

    public var description: String { "RNodeMultiInterface[\(name)]" }

    // MARK: – Incoming byte handler

    private func handleIncoming(_ data: Data) {
        let frames = decoder.feed(data)
        for (cmd, payload) in frames {
            processFrame(cmd: cmd, payload: payload)
        }
    }

    // MARK: – Frame dispatcher (Python: readLoop)

    private func processFrame(cmd: UInt8, payload: Data) {
        // ── CMD_SEL_INT: update selected sub-interface ──────────────────────────
        if cmd == KISS.cmdSelInt {
            if let b = payload.first {
                let idx = Int(b)
                if idx < subInterfaces.count { selectedIndex = idx }
            }
            return
        }

        // ── CMD_DATA (0x00 = CMD_INT0_DATA): route to selectedIndex ─────────────
        // Python: `if in_frame and byte == KISS.FEND and command == KISS.CMD_DATA:
        //              self.subinterfaces[self.selected_index].process_incoming(data_buffer)`
        // The CMD_SEL_INT frame preceding this one determined selectedIndex.
        if cmd == KISS.cmdData {
            guard selectedIndex < subInterfaces.count else { return }
            dispatchInboundData(payload, channelIndex: selectedIndex)
            return
        }

        // ── CMD_INTn_DATA (n > 0): index is encoded directly in the command byte ─
        // KISS.intDataCommands = [0x00, 0x10, 0x20, 0x70, 0x75, 0x90, 0xA0, 0xB0,
        //                         0xC0, 0xD0, 0xE0, 0xF0]
        // The position of cmd in that array IS the sub-interface index.
        // 0x10 → index 1, 0x20 → index 2, etc.
        if let idx = KISS.intDataCommands.firstIndex(of: cmd), idx > 0 {
            dispatchInboundData(payload, channelIndex: idx)
            return
        }

        // ── All other commands are telemetry/status for selectedIndex ───────────
        processCommandFrame(cmd: cmd, payload: payload)
    }

    private func dispatchInboundData(_ payload: Data, channelIndex: Int) {
        guard channelIndex < subInterfaces.count else { return }
        let sub = subInterfaces[channelIndex]
        sub.rxBytes += payload.count
        // Pass the RNodeSubInterface instance directly — it now conforms to Interface,
        // so callers can downcast `any Interface → RNodeSubInterface` for channel ID.
        if let h = rawInboundHandler {
            h(payload, sub)
        } else if let packet = try? Packet.unpack(payload) {
            inboundHandler?(packet, sub)
        }
    }

    // MARK: – Telemetry command dispatcher

    private func processCommandFrame(cmd: UInt8, payload: Data) {
        switch cmd {

        case KISS.cmdFrequency:
            if payload.count >= 4 {
                subInterfaces[selectedIndex].rFrequency = uint32BigEndian(payload)
            }

        case KISS.cmdBandwidth:
            if payload.count >= 4 {
                subInterfaces[selectedIndex].rBandwidth = uint32BigEndian(payload)
            }

        case KISS.cmdTxpower:
            if let b = payload.first { subInterfaces[selectedIndex].rTxPower = Int(b) }

        case KISS.cmdSf:
            if let b = payload.first { subInterfaces[selectedIndex].rSf = Int(b) }

        case KISS.cmdCr:
            if let b = payload.first { subInterfaces[selectedIndex].rCr = Int(b) }

        case KISS.cmdRadioState:
            if let b = payload.first { subInterfaces[selectedIndex].rState = b }

        case KISS.cmdRadioLock:
            if let b = payload.first { subInterfaces[selectedIndex].rLock = b }

        case KISS.cmdStatRssi:
            if let b = payload.first {
                subInterfaces[selectedIndex].rStatRssi = Int(b) - Self.rssiOffset
            }

        case KISS.cmdStatSnr:
            if let b = payload.first {
                let signed = Int8(bitPattern: b)
                let snr = Float(signed) * 0.25
                subInterfaces[selectedIndex].rStatSnr = snr
                computeSnrQuality(snr: snr, index: selectedIndex)
            }

        case KISS.cmdStAlock:
            if payload.count >= 2 {
                let at = (Int(payload[payload.startIndex]) << 8) | Int(payload[payload.startIndex + 1])
                subInterfaces[selectedIndex].rStAlock = Double(at) / 100.0
            }

        case KISS.cmdLtAlock:
            if payload.count >= 2 {
                let at = (Int(payload[payload.startIndex]) << 8) | Int(payload[payload.startIndex + 1])
                subInterfaces[selectedIndex].rLtAlock = Double(at) / 100.0
            }

        // ── Multi-interface global state ──────────────────────────────────────
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

        case KISS.cmdInterfaces:
            // Python: 2 bytes per interface [vport, type]; accumulate by pairs
            // We receive bytes two at a time between FENDs.
            // Each complete 2-byte buffer means one interface type entry.
            // payload contains all bytes after the command byte.
            processInterfacesPayload(payload)

        case KISS.cmdRandom:
            if let b = payload.first { subInterfaces[selectedIndex].rRandom = b }

        default:
            break
        }
    }

    /// Python: CMD_INTERFACES — each pair of bytes is [vport, interface_type]
    private func processInterfacesPayload(_ payload: Data) {
        var i = payload.startIndex
        while i + 1 < payload.endIndex {
            // Python: command_buffer[0] is vport (ignored), command_buffer[1] is type
            let typeCode = payload[i + 1]
            subInterfaceTypes.append(KISS.interfaceTypeToString(typeCode))
            i = i.advanced(by: 2)
        }
    }

    // MARK: – SNR quality (per sub-interface)

    private func computeSnrQuality(snr: Float, index: Int) {
        guard let sf = subInterfaces[index].rSf else { return }
        let sfs = sf - 7
        let qSnrMin = Self.qSnrMinBase - sfs * Self.qSnrStep
        let qSnrMax = Self.qSnrMax
        let span = qSnrMax - qSnrMin
        guard span > 0 else { subInterfaces[index].rStatQ = 0.0; return }
        var quality = (Double(snr) - Double(qSnrMin)) / Double(span) * 100.0
        quality = max(0.0, min(100.0, quality))
        subInterfaces[index].rStatQ = round(quality * 10.0) / 10.0
    }

    // MARK: – Private helpers

    /// Send a config command prefixed with CMD_SEL_INT for the given sub-interface.
    /// Python wire format: [FEND CMD_SEL_INT index FEND FEND cmd escaped_data FEND]
    private func sendConfigCommand(_ cmd: UInt8, data: Data, subInterface: RNodeSubInterface) throws {
        let escaped = KISS.escape(data)
        var frame = Data()
        frame.append(KISS.fend)
        frame.append(KISS.cmdSelInt)
        frame.append(UInt8(subInterface.index))
        frame.append(KISS.fend)
        frame.append(KISS.fend)
        frame.append(cmd)
        frame.append(escaped)
        frame.append(KISS.fend)
        try transport?.write(frame)
    }

    private func uint32ToData(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >>  8) & 0xFF),
            UInt8( value        & 0xFF)
        ])
    }

    private func uint32BigEndian(_ data: Data) -> UInt32 {
        let i = data.startIndex
        return (UInt32(data[i]) << 24) |
               (UInt32(data[i+1]) << 16) |
               (UInt32(data[i+2]) << 8)  |
                UInt32(data[i+3])
    }
}

// RNodeSubInterfaceProxy was removed: RNodeSubInterface now conforms to Interface directly,
// so it can be passed as `any Interface` and downcast back by callers.
