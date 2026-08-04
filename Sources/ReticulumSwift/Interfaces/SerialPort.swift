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

    /// Invoked when the device fails underneath the port — a read reporting the device gone
    /// (EOF or an errno) or a failed write. Required, with no defaulted no-op: a conformer
    /// that cannot report loss leaves its interface Up over a dead descriptor forever, which
    /// is the defect this seam closes. Python's equivalent is the blocking read loop raising
    /// into `reconnect_port` (`SerialInterface.py:196-221`).
    var onTransportError: ((Error) -> Void)? { get set }

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

// MARK: - TransportReconnector

/// Python's `reconnect_port` loop, shared by every serial-family interface: on device loss the
/// interface goes offline and redials every `wait` seconds until an attempt succeeds or the
/// interface is stopped (`SerialInterface.py:203-221`, `KISSInterface.py:371-380`,
/// `AX25KISSInterface.py:384-393`, `RNodeInterface.py:1167-1187` — all `while True:
/// sleep(5); try open`). One implementation so five interfaces cannot drift.
final class TransportReconnector {
    private let queue = DispatchQueue(label: "rns.transport.reconnect")
    private let lock = NSLock()
    private var generation = 0
    private var running = false

    /// Begin redialling. `attempt` returns true when the interface is back online; it runs on
    /// the reconnector's queue. Repeated calls while a loop is running are ignored, so
    /// overlapping failure signals collapse into one loop.
    func begin(wait: TimeInterval, attempt: @escaping () -> Bool) {
        lock.lock()
        if running { lock.unlock(); return }
        running = true
        let expected = generation
        lock.unlock()
        schedule(wait: wait, generation: expected, attempt: attempt)
    }

    /// Stop redialling. An in-flight attempt may still complete; no further ones fire.
    func cancel() {
        lock.lock()
        generation += 1
        running = false
        lock.unlock()
    }

    private func schedule(wait: TimeInterval, generation expected: Int,
                          attempt: @escaping () -> Bool) {
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let live = self.running && self.generation == expected
            self.lock.unlock()
            guard live else { return }
            if attempt() {
                self.lock.lock()
                if self.generation == expected { self.running = false }
                self.lock.unlock()
            } else {
                self.schedule(wait: wait, generation: expected, attempt: attempt)
            }
        }
    }
}
