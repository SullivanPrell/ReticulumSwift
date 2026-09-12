//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - KISS framing + full command set
// All CMD_* constants match the Python KISS class in RNodeInterface.py exactly.

// The members below are a byte table named after the reference's own constants;
// a per-constant summary would only restate the name.
// swift-format-ignore: AllPublicDeclarationsHaveDocumentation
/// KISS framing bytes and the full RNode command set.
///
/// Python: `RNS.Interfaces.RNodeInterface.KISS`.
public enum KISS {
    // ── Framing ──────────────────────────────────────────────────────────────
    public static let fend:  UInt8 = 0xC0
    public static let fesc:  UInt8 = 0xDB
    public static let tfend: UInt8 = 0xDC
    public static let tfesc: UInt8 = 0xDD

    // ── Data / command bytes ──────────────────────────────────────────────────
    /// Alias for backward compat with older callers that used `commandData`.
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

    // MARK:–KISS TNC protocol aliases (KISSInterface / AX25KISSInterface)
    // 0x01–0x06 overlap with RNode radio cmd bytes; semantics differ per interface type.
    public static let cmdTxDelay:     UInt8 = 0x01   // == cmdFrequency in RNode context
    public static let cmdP:           UInt8 = 0x02   // == cmdBandwidth in RNode context
    public static let cmdSlotTime:    UInt8 = 0x03   // == cmdTxpower in RNode context
    public static let cmdTxTail:      UInt8 = 0x04   // == cmdSf in RNode context
    public static let cmdFullDuplex:  UInt8 = 0x05   // == cmdCr in RNode context
    public static let cmdSetHardware: UInt8 = 0x06   // == cmdRadioState in RNode context
    public static let cmdReturn:      UInt8 = 0xFF

    // ── Multi-interface specific ──────────────────────────────────────────────
    /// CMD_SEL_INT: selects the active sub-interface for subsequent config commands.
    public static let cmdSelInt:      UInt8 = 0x1F
    /// CMD_INTERFACES: detect response lists hardware interface types.
    public static let cmdInterfaces:  UInt8 = 0x71

    /// Incoming data command bytes—one per sub-interface channel
    /// (command byte in KISS frame that carries data FROM a specific channel).
    public static let cmdInt0Data:  UInt8 = 0x00   // same as cmdData—channel 0
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

    /// Mapping from cmdIntNData values to sub-interface index (0-based).
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

    /// Returns a human-readable name for an RNode hardware interface type.
    ///
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

    // MARK:–KISS escape / frame helpers

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
    ///
    /// Equivalent to `frameData(data)` with `CMD_DATA`.
    public static func frame(_ data: Data) -> Data { frameData(data) }

    // MARK:–Frame decoder

    /// Stateful KISS frame decoder.
    ///
    /// Feed raw bytes as they arrive; receive `(command, payload)` pairs as
    /// frames complete. The command byte is the first byte inside each frame
    /// (after the opening FEND); the payload is everything that follows.
    ///
    /// Used by `RNodeInterface`, `RNodeMultiInterface`, `KISSInterface`, and
    /// `AX25KISSInterface`.
    public final class FrameDecoder {
        private var inFrame       = false
        private var pendingEscape = false
        private var buffer        = Data()

        /// Hard cap on an in-progress KISS frame.
        ///
        /// Far above any real RNode frame
        /// (MTU ~500 plus KISS escaping), so valid frames are never affected; it
        /// only bounds a garbage/malicious stream that never emits a closing FEND,
        /// which would otherwise grow `buffer` without limit.
        static let maxFrameBytes = 8192

        public init() {}

        /// Returns decoded `(command, payload)` pairs for each complete frame.
        public func feed(_ bytes: Data) -> [(command: UInt8, data: Data)] {
            var frames: [(UInt8, Data)] = []
            for byte in bytes {
                if buffer.count > FrameDecoder.maxFrameBytes {
                    // Runaway/unterminated frame—discard and resynchronize.
                    buffer.removeAll(keepingCapacity: false)
                    inFrame = false
                    pendingEscape = false
                }
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

/// KISS-framed interface to an RNode LoRa modem.
///
/// The byte-stream backing
/// it (USB-serial, CoreBluetooth Nordic UART, TCP, and so on) comes from the
/// host application as an `RNodeTransport`. This file owns KISS framing and
/// the full RNode configuration / telemetry command set.
public final class RNodeInterface: Interface {
    /// Per-interface mutable configuration (mode, announce rate control, ingress/egress
    /// control, the `ic_*` tunables).
    ///
    /// One stored property satisfies the whole settable set;
    /// see `InterfaceState` and `swift_devel/bugs/025-*.md`.
    public let interfaceState = InterfaceState()

    /// Python marks this type discoverable (`RNodeInterface.py:302`).
    ///
    /// The announcer
    /// still needs `discoverable` set from config before it announces anything.
    public let supportsDiscovery = true

    /// The live radio parameters published by the RNode announce branch
    /// (`Discovery.py:188-192`).
    public var discoveryRadioParameters: DiscoveryRadioParameters? {
        DiscoveryRadioParameters(frequency: Int(frequency), bandwidth: Int(bandwidth),
                                 spreadingFactor: sf, codingRate: cr)
    }

    /// Mirrors Python's `Interface.announces_to_internal` (RNS 1.4.1).
    public var announcesToInternal: Bool? = nil
    /// Mirrors Python's `Interface.gravity` (RNS 1.4.1).
    public var gravity: Int = InterfaceMode.defaultGravity

    // MARK:–Class constants (Python: RNodeInterface.XXXX)

    /// Hardware MTU in bytes for an RNode radio frame.
    public static let hwMtuValue:       Int    = 508
    /// Lowest frequency in Hz an RNode accepts.
    public static let freqMin:          UInt32 = 137_000_000
    /// Highest frequency in Hz an RNode accepts.
    public static let freqMax:          UInt32 = 3_000_000_000
    /// Offset added to the raw RSSI byte to recover dBm.
    public static let rssiOffset:       Int    = 157
    /// Maximum station identification callsign length in bytes.
    public static let callsignMaxLen:   Int    = 32
    /// Major firmware version this interface requires.
    public static let requiredFwVerMaj: UInt8  = 1
    /// Minor firmware version this interface requires.
    public static let requiredFwVerMin: UInt8  = 52
    /// Seconds to wait before reattempting a dropped device connection.
    public static let reconnectWait:    Int    = 5
    /// Lowest SNR in dB used when scaling link quality.
    public static let qSnrMinBase:      Int    = -9
    /// Highest SNR in dB used when scaling link quality.
    public static let qSnrMax:          Int    = 6
    /// SNR step in dB between link-quality levels.
    public static let qSnrStep:         Int    = 2

    /// Battery state reported before the device sends one.
    public static let batteryStateUnknown:     UInt8 = 0x00
    /// Battery state for a device running on battery.
    public static let batteryStateDischarging: UInt8 = 0x01
    /// Battery state for a device taking charge.
    public static let batteryStateCharging:    UInt8 = 0x02
    /// Battery state for a fully charged device.
    public static let batteryStateCharged:     UInt8 = 0x03

    // MARK:–Interface protocol

    /// Configured interface name.
    public let name:   String
    /// Hardware MTU in bytes.
    public var hwMtu:  Int?    { Self.hwMtuValue }
    /// Interface bitrate in bits per second, recomputed from the radio parameters.
    public var bitrate: Int = 0

    private let onlineFlag = LockedFlag(false)
    /// Whether the interface is up and carrying traffic.
    public var isOnline: Bool {
        get { onlineFlag.value }
        set { onlineFlag.value = newValue }
    }

    /// Called with each packet decoded from the radio.
    public var inboundHandler:    ((Packet, any Interface) -> Void)?
    /// Called with each KISS payload before packet decoding.
    public var rawInboundHandler: ((Data,   any Interface) -> Void)?
    /// Identity deriving the IFAC key, when IFAC is configured.
    public var ifacIdentity: Identity?
    /// IFAC key, when a network name or passphrase is configured.
    public var ifacKey:      Data?
    /// IFAC token size in bytes when a network name / passphrase is configured but no explicit
    /// `ifac_size` is given.
    ///
    /// Python declares 8 for the RNode family—`RNodeInterface.py:110`,
    /// `RNodeMultiInterface.py:137`—where TCP/UDP/Auto/Backbone/I2P/Weave declare 16. Using the
    /// global 16 here would drop 100%% of traffic on an IFAC-protected LoRa link to a Python peer
    /// while reporting the interface Up. See `swift_devel/bugs/025-*.md`.
    public static let defaultIfacSize: Int = 8

    /// IFAC token size in bytes.
    public var ifacSize:     Int = RNodeInterface.defaultIfacSize

    // MARK:–Transport

    /// Byte transport carrying KISS frames to the device.
    public weak var transport: RNodeTransport?
    private let decoder = KISS.FrameDecoder()

    // MARK:–Configured radio parameters (the requested values)

    /// Requested centre frequency in Hz.
    public var frequency:  UInt32 = 0
    /// Requested bandwidth in Hz.
    public var bandwidth:  UInt32 = 0
    /// Requested transmit power in dBm.
    public var txPower:    Int    = 0
    /// Requested spreading factor.
    public var sf:         Int    = 0   // spreading factor
    /// Requested coding rate.
    public var cr:         Int    = 0   // coding rate
    /// Requested radio state.
    public var state:      UInt8  = KISS.radioStateOff
    /// Requested short-term airtime limit, as a fraction.
    public var stAlock:    Double? = nil
    /// Requested long-term airtime limit, as a fraction.
    public var ltAlock:    Double? = nil

    // MARK:–Reported (echoed) radio parameters (what the device says it has)

    /// Centre frequency in Hz the device reports.
    public var rFrequency: UInt32? = nil
    /// Bandwidth in Hz the device reports.
    public var rBandwidth: UInt32? = nil
    /// Transmit power in dBm the device reports.
    public var rTxPower:   Int?    = nil
    /// Spreading factor the device reports.
    public var rSf:        Int?    = nil
    /// Coding rate the device reports.
    public var rCr:        Int?    = nil
    /// Radio state the device reports.
    public var rState:     UInt8?  = nil
    /// Airtime lock state the device reports.
    public var rLock:      UInt8?  = nil
    /// Short-term airtime limit the device reports.
    public var rStAlock:   Double? = nil
    /// Long-term airtime limit the device reports.
    public var rLtAlock:   Double? = nil

    // MARK:–Firmware / hardware info

    /// Major firmware version the device reports.
    public var majVersion:  UInt8 = 0
    /// Minor firmware version the device reports.
    public var minVersion:  UInt8 = 0
    /// Whether the reported firmware meets the required version.
    public var firmwareOk:  Bool  = false
    /// Whether the device answered the detect command.
    public var detected:    Bool  = false
    /// Hardware platform byte the device reports.
    public var platform:    UInt8? = nil
    /// Microcontroller byte the device reports.
    public var mcu:         UInt8? = nil
    /// Hardware error codes the device has reported.
    public var hwErrors:    [UInt8] = []

    // MARK:–Telemetry

    /// Received packet count the device reports.
    public var rStatRx:    UInt32? = nil
    /// Transmitted packet count the device reports.
    public var rStatTx:    UInt32? = nil
    /// RSSI in dBm for the last received packet.
    public var rStatRssi:  Int?    = nil
    /// SNR in dB for the last received packet.
    public var rStatSnr:   Float?  = nil
    /// Link quality for the last received packet, as a percentage.
    public var rStatQ:     Double? = nil
    /// Random byte the device last supplied.
    public var rRandom:    UInt8?  = nil

    /// Short-window airtime usage, as a fraction.
    public var rAirtimeShort:      Double = 0.0
    /// Long-window airtime usage, as a fraction.
    public var rAirtimeLong:       Double = 0.0
    /// Short-window channel load, as a fraction.
    public var rChannelLoadShort:  Double = 0.0
    /// Long-window channel load, as a fraction.
    public var rChannelLoadLong:   Double = 0.0
    /// Current channel RSSI in dBm.
    public var rCurrentRssi:       Int?   = nil
    /// Current noise floor in dBm.
    public var rNoiseFloor:        Int?   = nil
    /// Current interference level in dBm.
    public var rInterference:      Int?   = nil

    /// Symbol time in milliseconds for the current radio parameters.
    public var rSymbolTimeMs:    Double? = nil
    /// Symbol rate in symbols per second.
    public var rSymbolRate:      Int?    = nil
    /// Preamble length in symbols.
    public var rPreambleSymbols: Int?    = nil
    /// Preamble duration in milliseconds.
    public var rPreambleTimeMs:  Int?    = nil
    /// CSMA slot time in milliseconds.
    public var rCsmaSlotTimeMs:  Int?    = nil
    /// CSMA interframe space in milliseconds.
    public var rCsmaDifsMs:      Int?    = nil
    /// CSMA contention window band.
    public var rCsmaCwBand:      UInt8?  = nil
    /// Lowest CSMA contention window value.
    public var rCsmaCwMin:       UInt8?  = nil
    /// Highest CSMA contention window value.
    public var rCsmaCwMax:       UInt8?  = nil

    /// Battery state the device reports.
    public var rBatteryState:   UInt8 = RNodeInterface.batteryStateUnknown
    /// Battery charge the device reports, as a percentage.
    public var rBatteryPercent: UInt8 = 0
    /// Temperature in degrees Celsius the device reports.
    public var rTemperature:    Int?  = nil

    /// The radio's reported temperature, under the name the stats payload publishes.
    ///
    /// Upstream keeps a second stored attribute and assigns it alongside every write to
    /// `r_temperature` (`RNodeInterface.py:1067`). Aliasing instead of storing removes the only
    /// way the two can disagree, and `cpu_temp` has no other writer upstream.
    public var cpuTemp: Int? { rTemperature }

    // MARK:–Flow control / TX queue

    /// Python starts this `False` (`RNodeInterface.py:297`) and raises it only after a
    /// validated bring-up (`:459`); defaulting it true was half of the missing online gate.
    public var interfaceReady: Bool  = false
    /// Whether the device has asked the host to pause transmission.
    public var flowControl:    Bool  = false
    /// Frames held while flow control is asserted.
    public var packetQueue:    [Data] = []

    // MARK:–Station identification (`id_callsign` / `id_interval`)

    /// Encoded callsign transmitted for station identification, or nil when not configured.
    ///
    /// Python: `self.id_callsign = id_callsign.encode("utf-8")` (`RNodeInterface.py:336`).
    public var idCallsign: Data? = nil
    /// Seconds after the first transmission at which the callsign goes out.
    ///
    /// Python: `self.id_interval` (`:337`). Set together with `idCallsign` or not at all—the
    /// reference treats a lone half of the pair as no configuration (`:333`, `:342-343`).
    public var idInterval: TimeInterval? = nil
    /// When the first non-ID transmission since the last ID happened; nil right after an ID.
    ///
    /// Python: `self.first_tx` (`process_outgoing`, `:1018-1023`).
    private(set) var firstTx: TimeInterval? = nil
    private var idTimer: Timer? = nil

    /// Python's callsign length gate (`RNodeInterface.py:334`, `CALLSIGN_MAX_LEN`).
    public static let callsignMaxLength = 32

    // MARK:–Init

    /// Keeps a factory-created transport alive: `transport` is `weak` (an application usually
    /// owns its BLE controller), but a transport minted by `InterfaceTransportFactories` for a
    /// config block has no other owner, so the config path parks it here (`bugs/031`).
    internal var ownedTransport: AnyObject? = nil

    /// Creates an interface driving `transport`.
    public init(name: String, transport: RNodeTransport, bitrate: Int = 0) {
        self.name      = name
        self.transport = transport
        self.bitrate   = bitrate
        transport.byteHandler = { [weak self] data in self?.handleIncoming(data) }
    }

    // MARK:–Interface lifecycle

    /// Bound on the wait for the device's detect response.
    ///
    /// Python polls 5 s over TCP/BLE
    /// (`RNodeInterface.py:434-442`) and sleeps a fixed 0.2 s on serial (`:444`); this port's
    /// reads are event-driven, so one bounded poll serves every transport and exits the moment
    /// the response lands.
    public var detectTimeout: TimeInterval = 5.0

    /// Bound on the wait for the echoed radio parameters before `validateRadioState()` decides.
    ///
    /// Python sleeps a fixed 0.25–1.5 s by transport (`:662-664`) and compares once; polling to
    /// the same largest bound reaches the same decision without the fixed stall.
    public var validateTimeout: TimeInterval = 1.5

    /// Seconds between redial attempts after device loss; overridable for tests.
    ///
    /// Python's
    /// reconnect loop hardcodes `time.sleep(5)` (`RNodeInterface.py:1178`)—the class
    /// `reconnectWait` constant records the reference value, this carries the live one.
    public var reconnectWaitOverride: TimeInterval = TimeInterval(RNodeInterface.reconnectWait)
    private let reconnector = TransportReconnector()

    /// Where the bring-up's bounded waits run.
    ///
    /// **Never the caller's thread.** The bring-up waits for bytes the transport delivers, and
    /// the port's real BLE transport delivers them on the *same* serial queue its owner calls
    /// `start()` from (`RNodeScannerController` hands `CBCentralManager` one queue and calls
    /// `start()` from `onGATTReady`, which arrives on it). Blocking there waits for work it's
    /// itself preventing: the detect response can't be delivered until the wait gives up. A
    /// queue this interface owns can't be the delivery queue of any transport, so waiting on it
    /// is always safe.
    private let bringUpQueue = DispatchQueue(label: "ReticulumSwift.RNodeInterface.bringUp")

    /// Signalled when a bring-up reaches a terminal outcome—online, or failed and closed.
    private let bringUpSettled = DispatchSemaphore(value: 0)

    /// Opens the device, detects it and brings the radio up.
    public func start() throws {
        // Python `configure_device` (`RNodeInterface.py:424-467`): reset state, open, detect,
        // wait bounded; no answer closes the port and stays offline. On detect: initRadio,
        // validate the echoed parameters, and only then interface_ready/online. `online` gates
        // `process_outgoing` (`:708-710`)—reporting it before the modem is configured is a
        // healthy-looking interface whose radio is off, the exact `bugs/013` shape.
        //
        // The reference performs all of that synchronously in `__init__`, and it can: Python's
        // reads run in their own thread, so the constructor's sleeps never starve them. Here the
        // sequence is handed to `bringUpQueue` and `start()` returns immediately; a caller that
        // wants the reference's blocking semantics—and knows it isn't on the transport's
        // delivery thread—calls ``waitUntilOnline(timeout:)``.
        transport?.onTransportError = { [weak self] error in self?.handleTransportLoss(error) }
        resetRadioState()
        try transport?.open()
        try detect()
        bringUpQueue.async { [weak self] in self?.completeBringUp() }
    }

    /// Block until the bring-up begun by `start()` finishes, returning whether the interface came
    /// online.
    ///
    /// Must not be called from the transport's byte-delivery thread—see
    /// ``bringUpQueue``. `rnsd` bringing a config-file interface up is the intended caller.
    @discardableResult
    public func waitUntilOnline(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isOnline && Date() < deadline {
            if bringUpSettled.wait(timeout: .now() + 0.05) == .success { break }
        }
        return isOnline
    }

    /// The rest of `configure_device`, running off the caller's thread.
    private func completeBringUp() {
        defer { bringUpSettled.signal() }

        let detectDeadline = Date().addingTimeInterval(detectTimeout)
        while !detected && Date() < detectDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard detected else {
            Reticulum.log("Could not detect device for \(displayName)", level: .error)
            transport?.close()
            return
        }

        do { try initRadio() } catch {
            Reticulum.log("Could not configure radio for \(displayName): \(error)", level: .error)
            transport?.close()
            return
        }
        let validateDeadline = Date().addingTimeInterval(validateTimeout)
        while !validateRadioState() && Date() < validateDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard validateRadioState() else {
            Reticulum.log("After configuring \(displayName), the reported radio parameters "
                          + "did not match your configuration. Aborting RNode startup",
                          level: .error)
            transport?.close()
            return
        }

        interfaceReady = true
        isOnline = true
        Reticulum.log("\(displayName) is configured and powered up", level: .info)

        // The reference checks the ID deadline on its ~80 ms read loop (`:1142-1146`); this
        // port's reads are event-driven, so a coarse timer carries the check. One-second
        // resolution against intervals measured in minutes.
        if idCallsign != nil, idInterval != nil, idTimer == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.idTimer == nil else { return }
                let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.transmitIDIfDue()
                }
                RunLoop.main.add(timer, forMode: .common)
                self.idTimer = timer
            }
        }
    }

    /// Turns the radio off and closes the device.
    public func stop() {
        reconnector.cancel()
        transport?.onTransportError = nil
        idTimer?.invalidate()
        idTimer = nil
        transport?.close()
        isOnline = false
    }

    /// Device loss → offline → redial, re-running the whole `start()` gate: a re-powered RNode
    /// lost its radio configuration with its power, so reopening the port alone would bring
    /// back an interface whose modem is unconfigured—Python's `reconnect_port` ends in
    /// `configure_device` for the same reason (`RNodeInterface.py:1155-1187`).
    private func handleTransportLoss(_ error: Error) {
        Reticulum.log("\(displayName) lost its device (\(error)) — reconnecting", level: .error)
        isOnline = false
        interfaceReady = false
        reconnector.begin(wait: reconnectWaitOverride) { [weak self] in
            guard let self else { return true }
            // `start()` returns before the bring-up finishes, so reading `isOnline` on the next
            // line would report the *previous* attempt's outcome—always false, so the loop
            // would fire a second, spurious bring-up over a radio that had already recovered,
            // wiping its validated parameters mid-flight. Wait for the outcome this attempt
            // actually produced.
            do { try self.start() } catch { return false }
            return self.waitUntilOnline(timeout: self.detectTimeout + self.validateTimeout + 1)
        }
    }

    /// Transmits `packet` over the radio, queueing it when flow control is on.
    public func send(_ packet: Packet) throws {
        guard let transport, isOnline else { return }
        let raw = try packet.pack()
        // Python tracks the first transmission since the last station ID in `process_outgoing`
        // (`:1018-1023`): sending the callsign clears the marker, anything else arms it.
        if firstTx == nil { firstTx = Date().timeIntervalSince1970 }
        try transport.write(KISS.frameData(wrapIfac(raw)))
    }

    /// `RNodeInterface.py:1142-1146`: once anything has been transmitted, the callsign goes out
    /// `idInterval` after that first transmission, then the marker resets.
    private func transmitIDIfDue() {
        guard let callsign = idCallsign, let interval = idInterval,
              let first = firstTx, isOnline, let transport else { return }
        guard Date().timeIntervalSince1970 > first + interval else { return }
        Reticulum.log("Interface \(name) is transmitting beacon data: "
                      + (String(data: callsign, encoding: .utf8) ?? callsign.hexString),
                      level: .debug)
        firstTx = nil
        try? transport.write(KISS.frameData(callsign))
    }

    // MARK:–Incoming byte handler

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

    // MARK:–Command frame dispatcher (Python: readLoop elif chain)

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

    // MARK:–SNR quality

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

    // MARK:–Channel timing (CMD_STAT_CHTM, 11 bytes)

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

    // MARK:–PHY parameters (CMD_STAT_PHYPRM, 12 bytes)

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

    // MARK:–Error handling

    /// Record a hardware error code.
    ///
    /// All known codes and unknown ones are
    /// recorded identically. Bounded to the most recent `maxHwErrors` so a
    /// misbehaving/hostile RNode can't grow the list without limit.
    private static let maxHwErrors = 256
    private func handleError(_ code: UInt8) {
        hwErrors.append(code)
        if hwErrors.count > RNodeInterface.maxHwErrors {
            hwErrors.removeFirst(hwErrors.count - RNodeInterface.maxHwErrors)
        }
    }

    // MARK:–Bitrate computation (Python: updateBitrate)

    /// Recomputes `bitrate` from the current radio parameters.
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

    // MARK:–Radio configuration commands

    /// Asks the device for its detect, firmware, platform and MCU responses.
    ///
    /// Python: detect()—sends 4 KISS frames asking for detect / fw / platform / mcu
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

    /// Tells the device to leave the current network.
    ///
    /// Python: leave() → [FEND CMD_LEAVE 0xFF FEND]
    public func leave() throws {
        try transport?.write(Data([KISS.fend, KISS.cmdLeave, 0xFF, KISS.fend]))
    }

    /// Hard-resets the device.
    ///
    /// Python: hard_reset() → [FEND CMD_RESET 0xF8 FEND]
    public func hardReset() throws {
        try transport?.write(Data([KISS.fend, KISS.cmdReset, 0xF8, KISS.fend]))
    }

    /// Sends the configured centre frequency to the device.
    ///
    /// Python: setFrequency()—4-byte big-endian uint32, KISS-escaped
    public func setFrequency() throws {
        let data = uint32ToData(frequency)
        try sendCommand(KISS.cmdFrequency, data: data)
    }

    /// Sends the configured bandwidth to the device.
    ///
    /// Python: setBandwidth()—4-byte big-endian uint32, KISS-escaped
    public func setBandwidth() throws {
        let data = uint32ToData(bandwidth)
        try sendCommand(KISS.cmdBandwidth, data: data)
    }

    /// Sends the configured transmit power to the device.
    ///
    /// Python: setTXPower()—single byte
    public func setTxPower() throws {
        try sendCommand(KISS.cmdTxpower, data: Data([UInt8(clamping: txPower)]))
    }

    /// Sends the configured spreading factor to the device.
    ///
    /// Python: setSpreadingFactor()—single byte
    public func setSpreadingFactor() throws {
        try sendCommand(KISS.cmdSf, data: Data([UInt8(clamping: sf)]))
    }

    /// Sends the configured coding rate to the device.
    ///
    /// Python: setCodingRate()—single byte
    public func setCodingRate() throws {
        try sendCommand(KISS.cmdCr, data: Data([UInt8(clamping: cr)]))
    }

    /// Sends the configured short-term airtime limit to the device.
    ///
    /// Python: setSTALock—2-byte big-endian (int(alock*100))
    public func setStAlock() throws {
        guard let at = stAlock else { return }
        let v = Int(at * 100)
        let data = Data([UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
        try sendCommand(KISS.cmdStAlock, data: data)
    }

    /// Sends the configured long-term airtime limit to the device.
    ///
    /// Python: setLTALock—2-byte big-endian (int(alock*100))
    public func setLtAlock() throws {
        guard let at = ltAlock else { return }
        let v = Int(at * 100)
        let data = Data([UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
        try sendCommand(KISS.cmdLtAlock, data: data)
    }

    /// Sets the radio to state `s`.
    ///
    /// Python: setRadioState()
    public func setRadioState(_ s: UInt8) throws {
        state = s
        try sendCommand(KISS.cmdRadioState, data: Data([s]))
    }

    /// Sends the full radio configuration, then turns the radio on.
    ///
    /// Python: initRadio()—sends all config in order, then radio ON
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

    // MARK:–Firmware validation (Python: validate_firmware)

    /// Checks the reported firmware against the required version.
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

    // MARK:–Radio state validation (Python: validateRadioState)

    /// Reports whether the device echoed back every requested radio parameter.
    public func validateRadioState() -> Bool {
        // Python None-guards only the frequency comparison (`RNodeInterface.py:671`); the
        // bandwidth, txpower, sf and state comparisons are unconditional (`:674-685`), so a
        // device that echoed nothing is a mismatch. Guarding every comparison made validation
        // vacuously true against total silence—an unconfigured modem "validated".
        var valid = true
        if let rf = rFrequency, abs(Int(frequency) - Int(rf)) > 100 { valid = false }
        if rBandwidth != bandwidth { valid = false }
        if rTxPower   != txPower   { valid = false }
        if rSf        != sf        { valid = false }
        if rState     != state     { valid = false }
        return valid
    }

    // MARK:–Radio state reset (Python: reset_radio_state)

    /// Clears every reported radio parameter.
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

    // MARK:–TX queue (Python: queue / process_queue)

    /// Holds `data` until flow control clears.
    public func queue(_ data: Data) {
        packetQueue.append(data)
    }

    /// Sends as much of the queued traffic as flow control allows.
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

    // MARK:–Battery accessors (Python: get_battery_state / get_battery_percent)

    /// Returns the battery state the device reports.
    public func getBatteryState() -> UInt8 { rBatteryState }
    /// Returns the battery charge the device reports, as a percentage.
    public func getBatteryPercent() -> UInt8 { rBatteryPercent }

    /// Returns the battery state as a human-readable string.
    public func getBatteryStateString() -> String {
        switch rBatteryState {
        case RNodeInterface.batteryStateCharged:     return "charged"
        case RNodeInterface.batteryStateCharging:    return "charging"
        case RNodeInterface.batteryStateDischarging: return "discharging"
        default:                                      return "unknown"
        }
    }

    // MARK:–Private helpers

    /// Build a KISS command frame: FEND + cmd + escape(data) + FEND.
    private func sendCommand(_ cmd: UInt8, data: Data) throws {
        var frame = Data()
        frame.append(KISS.fend)
        frame.append(cmd)
        frame.append(KISS.escape(data))
        frame.append(KISS.fend)
        try transport?.write(frame)
    }

    /// Pack a UInt32 as 4-byte big-endian Data.
    private func uint32ToData(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >>  8) & 0xFF),
            UInt8( value        & 0xFF)
        ])
    }

    /// Read 4 bytes from Data as big-endian UInt32.
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

    /// Invoked when the device fails underneath the transport—a read reporting the device
    /// gone or a failed write. Required (no defaulted no-op): a conformer that can't report
    /// loss leaves the interface Up over a dead device forever, which is the defect this seam
    /// closes. Python's equivalent is the read loop raising into `reconnect_port`
    /// (`RNodeInterface.py:1155-1187`).
    var onTransportError: ((Error) -> Void)? { get set }

    func open()  throws
    func close()
    func write(_ data: Data) throws
}
