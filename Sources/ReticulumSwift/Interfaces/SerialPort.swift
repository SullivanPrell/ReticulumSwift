import Foundation

// MARK: - SerialParity

/// Parity mode for a serial port.
/// Mirrors Python pyserial PARITY_NONE / PARITY_EVEN / PARITY_ODD.
public enum SerialParity: Equatable {
    case none
    case even
    case odd

    /// Parse from an INI / Python config string.
    /// "N", "n", or anything unrecognised → `.none`
    /// "E", "e", "even", "Even", … → `.even`
    /// "O", "o", "odd",  "Odd",  … → `.odd`
    public init(string: String) {
        switch string.lowercased() {
        case "e", "even": self = .even
        case "o", "odd":  self = .odd
        default:          self = .none
        }
    }
}

// MARK: - SerialPortTransport

/// Abstraction over a physical (or mock) serial port.
///
/// Production code uses `PosixSerialPort` (macOS only); tests inject `MockSerialPort`.
public protocol SerialPortTransport: AnyObject {
    var isOpen: Bool { get }

    /// Open the port with the given parameters.
    func open(port: String,
              baudRate: Int,
              dataBits: Int,
              parity: SerialParity,
              stopBits: Int) throws

    /// Close the port.
    func close()

    /// Write data; returns number of bytes actually written.
    @discardableResult
    func write(_ data: Data) throws -> Int

    /// Register a callback that is invoked whenever bytes arrive on the port.
    func setReadCallback(_ callback: @escaping (Data) -> Void)
}
