import Foundation

// MARK: - The transport factory registry (`swift_devel/bugs/031`, design D6)

/// Resolves the device strings in a config file to the transports interface construction needs.
///
/// `RNodeInterface`, `KISSInterface`, `AX25KISSInterface` and `I2PInterface` all take an injected
/// transport by design — radio I/O is decoupled from BLE/USB, and serial ports exist on macOS
/// while BLE exists on iOS. That availability split lives *here*, as which factories are
/// registered, so `synthesizeInterfaces` contains no platform conditionals: it asks the registry
/// and either gets a transport or a thrown error naming what is missing.
///
/// The alternative — `#if os(iOS)` inside the construction switch — was rejected because the iOS
/// branch could never be exercised from a host-platform test run and would ship unobserved. With
/// a registry, a test registers a stub factory and drives both the constructed and the
/// unavailable path on any platform.
///
/// An application substitutes its own factory to extend a family — e.g. RetiOS registering a
/// CoreBluetooth-backed `rnode` factory for `ble://` device strings. Registration is
/// whole-closure replacement; a custom factory that wants the platform default for other device
/// strings calls `defaultRNodeFactory` from its own closure.
public enum InterfaceTransportFactories {

    /// Serial families (`KISSInterface`, `AX25KISSInterface`): a device path such as
    /// `/dev/ttyUSB0` becomes an unopened serial transport. Opening happens in the interface's
    /// own `start()`, so constructing an interface never touches hardware — absent hardware
    /// fails at bring-up with the cause, exactly as the reference's open failure does, while
    /// invalid *configuration* fails at construction (`RNodeInterface.py:346` vs `:354-360`).
    public static var serial: ((_ device: String) throws -> SerialPortTransport)? = defaultSerialFactory

    /// `RNodeInterface`: `/dev/tty…` resolves through the serial factory; `ble://…` needs a
    /// BLE-backed factory the application registers (CoreBluetooth is an app-side concern).
    public static var rnode: ((_ device: String) throws -> RNodeTransport)? = defaultRNodeFactory

    /// `I2PInterface`: the embedded i2pd daemon. Available on every Apple platform, because the
    /// CI2PD xcframework ships in this package.
    public static var i2pDaemon: (() throws -> I2PDaemonProtocol)? = { I2PDaemon() }

    /// What construction throws when a family has no registered factory, or the registered one
    /// cannot serve the device string. Deliberately loud: the defect class this closes is a
    /// daemon that starts, reports healthy, and silently does not have the radio the operator
    /// enabled.
    public enum FactoryError: Error, LocalizedError, Equatable {
        case unavailable(family: String, device: String, hint: String)

        public var errorDescription: String? {
            switch self {
            case .unavailable(let family, let device, let hint):
                return "no \(family) transport is available for device '\(device)' — \(hint)"
            }
        }
    }

    // MARK: Platform defaults

    /// POSIX serial on macOS; nothing elsewhere — iOS and its relatives have no serial devices,
    /// and the honest answer there is a thrown error, not a stub that opens nothing.
    static var defaultSerialFactory: ((String) throws -> SerialPortTransport)? {
        #if os(macOS)
        return { _ in POSIXSerialPort() }
        #else
        return nil
        #endif
    }

    /// `/dev/…` → the serial factory wrapped in the KISS-framing adapter an RNode speaks.
    /// `ble://…` is refused with the registration hint, on every platform — BLE lives in the
    /// application layer.
    static var defaultRNodeFactory: ((String) throws -> RNodeTransport)? {
        return { device in
            if device.hasPrefix("ble://") {
                throw FactoryError.unavailable(
                    family: "RNode BLE", device: device,
                    hint: "register a BLE-backed factory on "
                        + "InterfaceTransportFactories.rnode from the application")
            }
            guard let serialFactory = serial else {
                throw FactoryError.unavailable(
                    family: "serial", device: device,
                    hint: "this platform has no serial devices; use ble:// with an "
                        + "application-registered BLE factory")
            }
            return SerialRNodeTransport(device: device, serial: try serialFactory(device))
        }
    }
}

// MARK: - Named-device address resolution (`device = en0`)

/// Resolves the `device` interface-block key the way the reference does: to the named network
/// device's own addresses, so a listener binds to that device rather than the wildcard
/// (`UDPInterface.get_broadcast_for_if`, `TCPServerInterface.get_address_for_if`).
enum NetworkDeviceAddress {

    /// The device's IPv4 address, or nil if the device has none.
    static func address(for device: String) -> String? {
        firstIPv4(for: device, wantBroadcast: false)
    }

    /// The device's IPv4 broadcast address, or nil.
    static func broadcast(for device: String) -> String? {
        firstIPv4(for: device, wantBroadcast: true)
    }

    private static func firstIPv4(for device: String, wantBroadcast: Bool) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == device else { continue }
            let target = wantBroadcast ? entry.pointee.ifa_dstaddr : entry.pointee.ifa_addr
            guard let sockaddrPtr = target,
                  sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var addr = sockaddr_in()
            memcpy(&addr, sockaddrPtr, MemoryLayout<sockaddr_in>.size)
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil
            else { continue }
            return String(cString: buffer)
        }
        return nil
    }
}

// MARK: - Construction errors

/// A config block that names an interface but cannot produce it. Thrown from
/// `synthesizeInterfaces`, whose callers propagate — taking the daemon down with the cause,
/// which is the reference's own behaviour for a failed interface construction
/// (`Reticulum.py:1087-1090` logs and calls `RNS.panic()`).
public enum InterfaceConstructionError: Error, LocalizedError, Equatable {
    case missingKey(interface: String, key: String)
    case invalidValue(interface: String, key: String, value: String)

    public var errorDescription: String? {
        switch self {
        case .missingKey(let interface, let key):
            return "interface '\(interface)' is missing required key '\(key)'"
        case .invalidValue(let interface, let key, let value):
            return "interface '\(interface)' has an invalid value '\(value)' for '\(key)'"
        }
    }
}

// MARK: - Serial-backed RNode transport

/// An `RNodeTransport` over a plain serial port — the USB half of the BLE/USB split.
///
/// RNode framing (KISS escaping and command bytes) is the interface's business; this adapter
/// only moves bytes, matching what the reference's `self.serial` does for its
/// `RNodeInterface`.
public final class SerialRNodeTransport: RNodeTransport {
    public let device: String
    private let serial: SerialPortTransport
    /// RNode serial runs at 115200 8N1 (`RNodeInterface.py:139`: `speed = 115200`).
    public var baudRate: Int = 115_200

    public var byteHandler: ((Data) -> Void)?

    public init(device: String, serial: SerialPortTransport) {
        self.device = device
        self.serial = serial
    }

    public func open() throws {
        try serial.open(port: device, baudRate: baudRate, dataBits: 8, parity: .none, stopBits: 1)
        serial.setReadCallback { [weak self] data in self?.byteHandler?(data) }
    }

    public func close() { serial.close() }

    public func write(_ data: Data) throws { try serial.write(data) }
}

#if os(macOS)

// MARK: - POSIX serial port (macOS)

/// A real serial port over POSIX termios — the first concrete `SerialPortTransport` in the
/// package. Until it existed, every serial-family interface could only ever be constructed with
/// a test mock, which is half of how `bugs/031` stayed invisible: there was nothing a real
/// config *could* construct.
public final class POSIXSerialPort: SerialPortTransport {

    public enum SerialError: Error, LocalizedError {
        case openFailed(port: String, errno: Int32)
        case configurationFailed(port: String, errno: Int32)
        case unsupportedBaudRate(Int)
        case notOpen

        public var errorDescription: String? {
            switch self {
            case .openFailed(let port, let err):
                return "could not open \(port): \(String(cString: strerror(err)))"
            case .configurationFailed(let port, let err):
                return "could not configure \(port): \(String(cString: strerror(err)))"
            case .unsupportedBaudRate(let rate):
                return "unsupported baud rate \(rate)"
            case .notOpen:
                return "serial port is not open"
            }
        }
    }

    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "rns.serial.read")
    private var readCallback: ((Data) -> Void)?
    private let lock = NSLock()

    public init() {}

    public var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return fd >= 0
    }

    public func open(port: String, baudRate: Int, dataBits: Int,
                     parity: SerialParity, stopBits: Int) throws {
        lock.lock(); defer { lock.unlock() }
        guard fd < 0 else { return }

        let descriptor = Darwin.open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else { throw SerialError.openFailed(port: port, errno: errno) }

        var tty = termios()
        guard tcgetattr(descriptor, &tty) == 0 else {
            let err = errno; Darwin.close(descriptor)
            throw SerialError.configurationFailed(port: port, errno: err)
        }

        cfmakeraw(&tty)
        guard let speed = POSIXSerialPort.speedConstant(for: baudRate) else {
            Darwin.close(descriptor)
            throw SerialError.unsupportedBaudRate(baudRate)
        }
        cfsetispeed(&tty, speed)
        cfsetospeed(&tty, speed)

        tty.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tty.c_cflag &= ~tcflag_t(CSIZE)
        switch dataBits {
        case 5: tty.c_cflag |= tcflag_t(CS5)
        case 6: tty.c_cflag |= tcflag_t(CS6)
        case 7: tty.c_cflag |= tcflag_t(CS7)
        default: tty.c_cflag |= tcflag_t(CS8)
        }
        switch parity {
        case .none: tty.c_cflag &= ~tcflag_t(PARENB)
        case .even: tty.c_cflag |= tcflag_t(PARENB); tty.c_cflag &= ~tcflag_t(PARODD)
        case .odd:  tty.c_cflag |= tcflag_t(PARENB); tty.c_cflag |= tcflag_t(PARODD)
        }
        if stopBits == 2 { tty.c_cflag |= tcflag_t(CSTOPB) } else { tty.c_cflag &= ~tcflag_t(CSTOPB) }

        // Non-blocking reads through the dispatch source; VMIN/VTIME zeroed accordingly.
        tty.c_cc.16 = 0   // VMIN
        tty.c_cc.17 = 0   // VTIME

        guard tcsetattr(descriptor, TCSANOW, &tty) == 0 else {
            let err = errno; Darwin.close(descriptor)
            throw SerialError.configurationFailed(port: port, errno: err)
        }

        fd = descriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return }
            let data = Data(buffer[0..<count])
            self.lock.lock(); let callback = self.readCallback; self.lock.unlock()
            callback?(data)
        }
        source.resume()
        readSource = source
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        readSource?.cancel()
        readSource = nil
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }

    @discardableResult
    public func write(_ data: Data) throws -> Int {
        lock.lock(); let descriptor = fd; lock.unlock()
        guard descriptor >= 0 else { throw SerialError.notOpen }
        return data.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return Darwin.write(descriptor, base, raw.count)
        }
    }

    public func setReadCallback(_ callback: @escaping (Data) -> Void) {
        lock.lock(); readCallback = callback; lock.unlock()
    }

    private static func speedConstant(for baudRate: Int) -> speed_t? {
        switch baudRate {
        case 1200:    return speed_t(B1200)
        case 2400:    return speed_t(B2400)
        case 4800:    return speed_t(B4800)
        case 9600:    return speed_t(B9600)
        case 19200:   return speed_t(B19200)
        case 38400:   return speed_t(B38400)
        case 57600:   return speed_t(B57600)
        case 115200:  return speed_t(B115200)
        case 230400:  return speed_t(B230400)
        default:      return nil
        }
    }
}

#endif
