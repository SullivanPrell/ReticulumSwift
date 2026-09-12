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

// MARK: - Errors

/// Errors raised by the serial interface.
public enum SerialInterfaceError: Error {
    case portNotFound(String)
    case portOpenFailed(String)
    case writeError(written: Int, expected: Int)
}

// MARK: - SerialInterface

/// HDLC-framed serial interface.
///
/// Wire-compatible with Python `RNS/Interfaces/SerialInterface.py`.
/// Uses the same HDLC byte-stuffing as TCPInterface / BackboneInterface.
///
/// The actual serial port I/O is delegated to a `SerialPortTransport` so
/// the interface can be unit-tested without physical hardware.
public final class SerialInterface: Interface {
    /// Per-interface mutable configuration (mode, announce rate control, ingress/egress
    /// control, the `ic_*` tunables).
    ///
    /// One stored property satisfies the whole settable set;
    /// see `InterfaceState` and `swift_devel/bugs/025-*.md`.
    public let interfaceState = InterfaceState()

    /// Mirrors Python's `Interface.announces_to_internal` (RNS 1.4.1).
    public var announcesToInternal: Bool? = nil
    /// Mirrors Python's `Interface.gravity` (RNS 1.4.1).
    public var gravity: Int = InterfaceMode.defaultGravity

    // MARK: - Class constants

    /// Maximum bytes written to the serial port in one call.
    ///
    /// Python: `MAX_CHUNK = 32768`
    public static let maxChunk: Int = 32_768

    /// Default IFAC authentication field size in bytes.
    ///
    /// Python: `DEFAULT_IFAC_SIZE = 8`
    public static let defaultIfacSize: Int = 8

    /// Hardware maximum transmission unit in bytes.
    ///
    /// Python: `self.HW_MTU = 564`
    public static let hwMtuConstant: Int = 564

    // MARK: - Interface protocol properties

    /// Interface name as it appears in configuration and status output.
    public let  name:    String
    /// Nominal interface bitrate in bits per second.
    public var  bitrate: Int
    private let onlineFlag = LockedFlag(false)
    /// Whether the interface is up and able to carry traffic.
    public private(set) var isOnline: Bool {
        get { onlineFlag.value }
        set { onlineFlag.value = newValue }
    }

    /// Lock-guarded—written from this interface's I/O queue while the UI
    /// and status reporting read from another thread.
    ///
    /// See `InterfaceCounters`.
    private let counters = InterfaceCounters()
    /// Total bytes received on this interface.
    public var rxBytes:   Int { counters.rxBytes }
    /// Total bytes transmitted on this interface.
    public var txBytes:   Int { counters.txBytes }
    /// Total packets received on this interface.
    public var rxPackets: Int { counters.rxPackets }
    /// Total packets transmitted on this interface.
    public var txPackets: Int { counters.txPackets }

    /// Hardware maximum transmission unit in bytes, or `nil` when unconstrained.
    public var hwMtu: Int? { SerialInterface.hwMtuConstant }

    /// Called with each packet decoded from an inbound frame.
    public var inboundHandler:    ((Packet, any Interface) -> Void)? = nil
    /// Called with each inbound frame, before packet decoding.
    public var rawInboundHandler: ((Data,   any Interface) -> Void)? = nil

    /// Identity authenticating this interface under IFAC, or `nil` when IFAC is off.
    public var ifacIdentity: Identity? = nil
    /// Derived IFAC key used to sign and verify frames.
    public var ifacKey:      Data?     = nil
    /// IFAC authentication field size in bytes.
    public var ifacSize:     Int       = SerialInterface.defaultIfacSize

    /// Whether the interface asks Transport to establish a tunnel over it.
    public var wantsTunnel: Bool  = false
    /// Identifier of the transport tunnel established over this interface.
    public var tunnelID:    Data? = nil

    // MARK: - Serial configuration

    /// Device path (for example, `/dev/cu.usbserial-0001`).
    public let port: String

    /// Baud rate.
    ///
    /// Python default: `9600`.
    public let speed: Int

    /// Data bits per character.
    ///
    /// Python default: `8`.
    public let dataBits: Int

    /// Parity mode.
    ///
    /// Python default: `PARITY_NONE`.
    public let parity: SerialParity

    /// Stop bits.
    ///
    /// Python default: `1`.
    public let stopBits: Int

    // MARK: - Private

    private let transport: SerialPortTransport
    private let decoder  = HDLC.FrameDecoder()

    // MARK: - Init

    /// Create a SerialInterface.
    ///
    /// - Parameters:
    ///   - name:      Interface name (for example, `"Serial0"`).
    ///   - port:      Device path.
    ///   - speed:     Baud rate (default `9600`). `bitrate` is set equal to this.
    ///   - dataBits:  Data bits (default `8`).
    ///   - parity:    Parity (default `.none`).
    ///   - stopBits:  Stop bits (default `1`).
    ///   - transport: Serial port transport (inject mock for tests).
    public init(name:      String,
                port:      String,
                speed:     Int          = 9600,
                dataBits:  Int          = 8,
                parity:    SerialParity = .none,
                stopBits:  Int          = 1,
                transport: SerialPortTransport) {
        self.name      = name
        self.port      = port
        self.speed     = speed
        self.dataBits  = dataBits
        self.parity    = parity
        self.stopBits  = stopBits
        self.bitrate   = speed
        self.transport = transport
    }

    /// Convenience init that parses parity from an INI config string ("N", "E", "O").
    ///
    /// Disambiguated from the designated init via the `parityString:` label.
    public convenience init(name:         String,
                            port:         String,
                            speed:        Int    = 9600,
                            dataBits:     Int    = 8,
                            parityString: String,
                            stopBits:     Int    = 1,
                            transport:    SerialPortTransport) {
        self.init(name: name, port: port,
                  speed: speed, dataBits: dataBits,
                  parity: SerialParity(string: parityString),
                  stopBits: stopBits, transport: transport)
    }

    // MARK: - Interface lifecycle

    /// Seconds between redial attempts after device loss.
    ///
    /// Python's reconnect loop hardcodes
    /// `time.sleep(5)` (`SerialInterface.py:210`).
    public var reconnectWait: TimeInterval = 5.0
    private let reconnector = TransportReconnector()

    /// Open the serial port and bring the interface online.
    public func start() throws {
        transport.onTransportError = { [weak self] error in self?.handleTransportLoss(error) }
        try transport.open(port: port, baudRate: speed,
                           dataBits: dataBits, parity: parity, stopBits: stopBits)
        transport.setReadCallback { [weak self] data in
            self?.feedBytes(data)
        }
        isOnline = true
    }

    /// Take the interface offline and close the serial port.
    public func stop() {
        reconnector.cancel()
        transport.onTransportError = nil
        isOnline = false
        transport.close()
    }

    /// The device failed underneath the port: go offline and redial until it answers, as
    /// Python's read loop does when it raises into `reconnect_port`
    /// (`SerialInterface.py:196-221`).
    private func handleTransportLoss(_ error: Error) {
        Reticulum.log("\(displayName) lost its serial device (\(error)) — reconnecting",
                      level: .error)
        isOnline = false
        reconnector.begin(wait: reconnectWait) { [weak self] in
            guard let self else { return true }   // interface gone: end the loop
            try? self.start()
            return self.isOnline
        }
    }

    // MARK: - Outgoing

    /// Send a Reticulum packet.
    ///
    /// Called by Transport.
    ///
    /// Applies the IFAC mask (when an IFAC key is configured) before framing,
    /// mirroring the central IFAC application in Python `Transport.transmit`.
    /// Without this, frames go out un-masked and IFAC-protected Python peers
    /// drop them ("IFAC flag not set but should be").
    public func send(_ packet: Packet) throws {
        guard let raw = try? packet.pack() else { return }
        processOutgoing(wrapIfac(raw))
    }

    /// HDLC-frame `data` and write to the serial port.
    ///
    /// Python: `process_outgoing(data)`—wraps in FLAG delimiters, writes to serial.
    public func processOutgoing(_ data: Data) {
        guard isOnline else { return }
        let framed = HDLC.frame(data)
        // Counted only when the write succeeded: a failed write counted as traffic is how a
        // flapped device kept showing healthy growing TX counters in rnstatus. The failure
        // itself reaches `handleTransportLoss` through the transport's error callback.
        guard (try? transport.write(framed)) != nil else { return }
        counters.addTx(bytes: framed.count)   // Python counts framed bytes
    }

    // MARK: - Incoming (bytes from the serial port)

    /// Feed raw bytes from the serial port.
    ///
    /// HDLC frames are extracted; each complete frame is delivered to
    /// `rawInboundHandler` (IFAC path) or parsed and sent to `inboundHandler`.
    public func feedBytes(_ data: Data) {
        // Pass the hardware MTU / IFAC size so the HDLC decoder bounds its receive
        // buffer (as the TCP/Backbone interfaces already do). Without this an
        // unterminated or garbage frame grows the decoder buffer without limit.
        let frames = decoder.feed(data, hwMtu: hwMtu, ifacSize: ifacSize)
        for frame in frames {
            counters.addRx(bytes: frame.count)  // Python counts payload bytes
            rawInboundHandler?(frame, self)
        }
    }
}
