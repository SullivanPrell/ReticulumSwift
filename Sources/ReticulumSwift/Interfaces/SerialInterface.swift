import Foundation

// MARK: - Errors

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

    // MARK: - Class constants

    /// Python: `MAX_CHUNK = 32768`
    public static let maxChunk: Int = 32_768

    /// Python: `DEFAULT_IFAC_SIZE = 8`
    public static let defaultIfacSize: Int = 8

    /// Python: `self.HW_MTU = 564`
    public static let hwMtuConstant: Int = 564

    // MARK: - Interface protocol properties

    public let  name:    String
    public var  bitrate: Int
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

    public var hwMtu: Int? { SerialInterface.hwMtuConstant }

    public var inboundHandler:    ((Packet, any Interface) -> Void)? = nil
    public var rawInboundHandler: ((Data,   any Interface) -> Void)? = nil

    public var ifacIdentity: Identity? = nil
    public var ifacKey:      Data?     = nil
    public var ifacSize:     Int       = SerialInterface.defaultIfacSize

    public var wantsTunnel: Bool  = false
    public var tunnelID:    Data? = nil

    // MARK: - Serial configuration

    /// Device path (e.g. `/dev/cu.usbserial-0001`).
    public let port: String

    /// Baud rate. Python default: `9600`.
    public let speed: Int

    /// Data bits per character. Python default: `8`.
    public let dataBits: Int

    /// Parity mode. Python default: `PARITY_NONE`.
    public let parity: SerialParity

    /// Stop bits. Python default: `1`.
    public let stopBits: Int

    // MARK: - Private

    private let transport: SerialPortTransport
    private let decoder  = HDLC.FrameDecoder()

    // MARK: - Init

    /// Create a SerialInterface.
    ///
    /// - Parameters:
    ///   - name:      Interface name (e.g. `"Serial0"`).
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

    /// Open the serial port and bring the interface online.
    public func start() throws {
        try transport.open(port: port, baudRate: speed,
                           dataBits: dataBits, parity: parity, stopBits: stopBits)
        transport.setReadCallback { [weak self] data in
            self?.feedBytes(data)
        }
        isOnline = true
    }

    /// Take the interface offline and close the serial port.
    public func stop() {
        isOnline = false
        transport.close()
    }

    // MARK: - Outgoing

    /// Send a Reticulum packet.  Called by Transport.
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
    /// Python: `process_outgoing(data)` — wraps in FLAG delimiters, writes to serial.
    public func processOutgoing(_ data: Data) {
        guard isOnline else { return }
        let framed = HDLC.frame(data)
        try? transport.write(framed)
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
