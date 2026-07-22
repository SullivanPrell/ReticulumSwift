import Foundation

// MARK: - I2PInterfacePeer

/// One end-to-end I2P tunnel connection, carrying HDLC-framed RNS packets.
/// Python: `I2PInterfacePeer(Interface)` (I2PInterface.py)
///
/// Wire format: identical to BackboneInterface — HDLC framing over a TCP byte
/// stream. The byte stream here is a SAM 3.1 stream to the remote destination,
/// provided by the local i2pd daemon (transparent to the framing layer).
///
/// Outbound (initiator) peers dial through SAM on a dedicated queue —
/// mirroring Python's thread-per-peer `tunnel_job`/`wait_job` model:
///
///   1. `NAMING LOOKUP` resolves a `.b32.i2p` address to a base64 destination
///   2. `SESSION CREATE` opens a control connection (held for the session's
///      lifetime — closing it destroys the session)
///   3. `STREAM CONNECT` turns a third connection into the raw data pipe
///
/// Failures at any step retry after `retryInterval` (Python: RECONNECT_WAIT),
/// and a watchdog sends idle keepalives / kills unresponsive tunnels exactly
/// like Python's `read_watchdog`.
public final class I2PInterfacePeer: Interface {

    // MARK: - Python class constants

    /// Python: `RECONNECT_WAIT = 15`
    public static let reconnectWait:     Int  = 15
    /// Python: `RECONNECT_MAX_TRIES = None` (unlimited)
    public static let reconnectMaxTries: Int? = nil

    /// Python: `I2P_USER_TIMEOUT = 45`
    public static let i2pUserTimeout:   Int = 45
    /// Python: `I2P_PROBE_AFTER = 10`
    public static let i2pProbeAfter:    Int = 10
    /// Python: `I2P_PROBE_INTERVAL = 9`
    public static let i2pProbeInterval: Int = 9
    /// Python: `I2P_PROBES = 5`
    public static let i2pProbes:        Int = 5
    /// Python: `I2P_READ_TIMEOUT = (I2P_PROBE_INTERVAL * I2P_PROBES + I2P_PROBE_AFTER) * 2`
    public static let i2pReadTimeout: Int = (i2pProbeInterval * i2pProbes + i2pProbeAfter) * 2

    // MARK: - Tunnel state

    /// Python: `TUNNEL_STATE_*` constants.
    public enum TunnelState: UInt8 {
        case initializing = 0x00    // TUNNEL_STATE_INIT
        case active       = 0x01    // TUNNEL_STATE_ACTIVE
        case stale        = 0x02    // TUNNEL_STATE_STALE
    }

    // MARK: - Interface protocol properties

    public let name: String
    public var bitrate: Int = I2PInterface.bitrateGuess
    private let onlineFlag = LockedFlag(false)
    public private(set) var isOnline: Bool {
        get { onlineFlag.value }
        set { onlineFlag.value = newValue }
    }
    /// Python alias: `self.online`
    public var online: Bool { isOnline }

    /// Python: `self.HW_MTU = 1064`
    public let hwMtu: Int? = I2PInterface.hwMtu

    public var inboundHandler:    ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?

    public var ifacIdentity: Identity?
    public var ifacKey:      Data?
    public var ifacSize:     Int = I2PInterface.defaultIfacSize

    /// Python wait_job: `self.wants_tunnel = True` before connecting, so
    /// Transport synthesizes a tunnel when the peer is registered.
    public var wantsTunnel: Bool = false
    public var tunnelID:    Data?
    public var bootstrapOnly: Bool = false

    /// Lock-guarded — the existing `lock` serialized writers only, leaving a
    /// reader on another thread racing every increment. See `InterfaceCounters`.
    private let counters = InterfaceCounters()
    public var rxBytes: Int { counters.rxBytes }
    public var txBytes: Int { counters.txBytes }
    // Each add() above corresponds to exactly one reassembled frame, so the
    // packet counts are already tracked — surfacing them lets the parent
    // `I2PInterface` report a meaningful total instead of a hardcoded 0.
    public var rxPackets: Int { counters.rxPackets }
    public var txPackets: Int { counters.txPackets }

    /// Python: `__str__` returns `"I2PInterfacePeer[<name>]"`.
    public var displayName: String { "I2PInterfacePeer[\(name)]" }

    // MARK: - I2P-specific properties

    public let initiator:   Bool
    public var kissFraming: Bool = false
    public var i2pTunneled: Bool = true
    public private(set) var tunnelState: TunnelState = .initializing

    /// Optional back-reference to parent interface.
    /// Python: outbound config peers have `parent_count = False`, so traffic
    /// is *not* rolled up into the parent's counters.
    public weak var parentInterface: I2PInterface?

    // MARK: - Dial configuration (overridable; defaults mirror Python)

    /// SAM bridge TCP port of the local i2pd daemon.
    public var samPort: Int = 7656
    /// Creates one SAM connection. Defaults to `NWSAMSocket` on `samPort`;
    /// tests inject scripted sockets (RNodeTransport pattern).
    public var socketFactory: (() -> SAMSocket)?
    /// Seconds between dial attempts. Python: `RECONNECT_WAIT`.
    public var retryInterval: TimeInterval = TimeInterval(I2PInterfacePeer.reconnectWait)
    /// Max seconds to wait for one SAM reply line. SESSION CREATE on a cold
    /// i2pd only answers once the local destination's tunnels are built,
    /// which can take minutes — be generous.
    public var handshakeTimeout: TimeInterval = 180
    /// Idle seconds before keepalives flow. Python: `I2P_PROBE_AFTER`.
    public var probeAfterInterval: TimeInterval = TimeInterval(I2PInterfacePeer.i2pProbeAfter)
    /// Seconds without any inbound bytes before the tunnel is declared dead.
    /// Python: `I2P_READ_TIMEOUT`.
    public var readTimeoutInterval: TimeInterval = TimeInterval(I2PInterfacePeer.i2pReadTimeout)
    /// Watchdog cadence. Python's read_watchdog ticks every 1 s.
    public var watchdogTick: TimeInterval = 1

    /// Fired when the peer comes online (tunnel + stream established).
    public var onConnected:    ((I2PInterfacePeer) -> Void)?
    /// Fired when an online peer loses its tunnel (also on `stop()`).
    public var onDisconnected: ((I2PInterfacePeer) -> Void)?

    // MARK: - Private state (guarded by `lock`)

    private let lock = NSLock()
    private var detached = false
    private var controlSocket: SAMSocket?
    private var streamSocket:  SAMSocket?
    private var lastRead:  Date = .distantPast
    private var lastWrite: Date = .distantPast

    private let dialQueue: DispatchQueue
    private let watchdogQueue: DispatchQueue
    private var watchdog: DispatchSourceTimer?

    private let targetDestination: String

    // MARK: - HDLC decoder state (private)

    private var inFrame   = false
    private var escape    = false
    private var rxBuffer  = Data()

    // MARK: - Init (outbound peer — targets a remote I2P destination)

    /// Python: `I2PInterfacePeer.__init__(..., target_i2p_dest=…)`
    public init(name: String,
                targetI2PDestination: String,
                parentInterface: I2PInterface?) {
        self.name              = name
        self.initiator         = true
        self.parentInterface   = parentInterface
        self.targetDestination = targetI2PDestination
        self.dialQueue = DispatchQueue(label: "ReticulumSwift.I2PInterfacePeer.dial.\(name)")
        self.watchdogQueue = DispatchQueue(label: "ReticulumSwift.I2PInterfacePeer.wd.\(name)")
    }

    // MARK: - Interface lifecycle

    /// Begin dialing the remote destination through SAM. Non-blocking; the
    /// peer comes online asynchronously (and keeps retrying — I2P tunnels can
    /// take minutes to build on a cold daemon).
    public func start() throws {
        lock.lock(); detached = false; lock.unlock()
        scheduleDial(after: 0)
    }

    /// Detach the peer: close the tunnel and stop reconnecting.
    /// Python: `detach()` + the `self.detached` guard in read_loop.
    public func stop() {
        lock.lock()
        detached = true
        let wasOnline = isOnline
        isOnline = false
        let sockets = [controlSocket, streamSocket].compactMap { $0 }
        controlSocket = nil
        streamSocket = nil
        lock.unlock()

        stopWatchdog()
        sockets.forEach { $0.close() }
        if wasOnline { onDisconnected?(self) }
    }

    // MARK: - Outbound send

    public func send(_ packet: Packet) throws {
        let raw = try packet.pack()
        processOutgoing(wrapIfac(raw))
    }

    /// HDLC-frame `data` and write it to the I2P stream.
    /// Python: `process_outgoing` — note Python counts the *framed* length
    /// (`txb += len(data)` after framing), unlike TCPInterface.
    public func processOutgoing(_ data: Data) {
        lock.lock()
        guard isOnline, let stream = streamSocket else { lock.unlock(); return }
        lastWrite = Date()
        lock.unlock()

        let framed = hdlcFrame(data)
        stream.write(framed)
        counters.addTx(bytes: framed.count)
    }

    // MARK: - SAM dial state machine

    private func scheduleDial(after delay: TimeInterval) {
        dialQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.dialOnce()
        }
    }

    private func dialOnce() {
        lock.lock()
        let stop = detached || isOnline
        lock.unlock()
        guard !stop else { return }

        do {
            try performDial()
        } catch {
            Reticulum.log("Error while configuring \(displayName): \(error)", level: .error)
            Reticulum.log("Check that I2P is running and SAM is enabled. Retrying tunnel setup later.", level: .error)
            cleanupSockets()
            lock.lock(); let retry = !detached; lock.unlock()
            if retry { scheduleDial(after: retryInterval) }
        }
    }

    private func makeSocket() -> SAMSocket {
        socketFactory?() ?? NWSAMSocket(port: UInt16(samPort))
    }

    /// One full dial attempt: resolve → session → stream → online.
    private func performDial() throws {
        Reticulum.log("Bringing up I2P tunnel to \(displayName), this may take a while...", level: .info)

        // 1. Resolve .i2p / .b32.i2p names to a full base64 destination.
        //    (i2plib does the same NAMING LOOKUP before STREAM CONNECT.)
        var destination = targetDestination
        if targetDestination.hasSuffix(".i2p") {
            let lookup = makeSocket()
            defer { lookup.close() }
            try handshake(lookup)
            lookup.write(Data(SAMClient.namingLookupLine(name: targetDestination).utf8))
            let reply = try lookup.readLine(timeout: handshakeTimeout)
            guard case .ok(let value) = SAMClient.parseNamingReply(reply) else {
                throw SAMSocketError.samFailure("NAMING LOOKUP failed: \(reply)")
            }
            destination = value
        }

        // 2. Create the stream session on a control connection that stays
        //    open — i2pd destroys the session when this socket closes.
        let sessionID = SAMClient.randomSessionID()
        let control = makeSocket()
        do {
            try handshake(control)
            control.write(Data(SAMClient.sessionCreateLine(sessionID: sessionID).utf8))
            let reply = try control.readLine(timeout: handshakeTimeout)
            guard case .ok = SAMClient.parseSessionStatus(reply) else {
                throw SAMSocketError.samFailure("SESSION CREATE failed: \(reply)")
            }
        } catch {
            control.close()
            throw error
        }

        // 3. Connect the data stream to the remote destination.
        let stream = makeSocket()
        do {
            try handshake(stream)
            stream.write(Data(SAMClient.streamConnectLine(sessionID: sessionID,
                                                          destination: destination).utf8))
            let reply = try stream.readLine(timeout: handshakeTimeout)
            guard case .ok = SAMClient.parseStreamStatus(reply) else {
                throw SAMSocketError.samFailure("STREAM CONNECT failed: \(reply)")
            }
        } catch {
            control.close()
            stream.close()
            throw error
        }

        // 4. Tunnel is up — go online and hand the socket to the data phase.
        wantsTunnel = !kissFraming   // Python wait_job, before connect()
        lock.lock()
        if detached {
            // stop() raced the dial — drop everything.
            lock.unlock()
            control.close()
            stream.close()
            return
        }
        controlSocket = control
        streamSocket = stream
        isOnline = true
        tunnelState = .active
        lastRead = Date()
        lastWrite = Date()
        // Fresh connection — reset the HDLC decoder (Python re-inits these
        // locals at the top of every read_loop).
        inFrame = false
        escape = false
        rxBuffer.removeAll()
        lock.unlock()

        stream.startStreaming({ [weak self] data in
            self?.handleStreamBytes(data, from: stream)
        }, onClose: { [weak self] in
            self?.handleStreamClosed(stream)
        })

        startWatchdog()
        Reticulum.log("\(displayName) tunnel setup complete", level: .verbose)
        onConnected?(self)
    }

    /// SAM HELLO exchange on a fresh connection.
    private func handshake(_ socket: SAMSocket) throws {
        try socket.connect(timeout: handshakeTimeout)
        socket.write(Data(SAMClient.helloLine.utf8))
        let reply = try socket.readLine(timeout: handshakeTimeout)
        guard case .ok = SAMClient.parseHelloReply(reply) else {
            throw SAMSocketError.samFailure("SAM HELLO failed: \(reply)")
        }
    }

    /// Close any half-built connections after a failed dial attempt.
    private func cleanupSockets() {
        lock.lock()
        let sockets = [controlSocket, streamSocket].compactMap { $0 }
        controlSocket = nil
        streamSocket = nil
        lock.unlock()
        sockets.forEach { $0.close() }
    }

    // MARK: - Data phase

    private func handleStreamBytes(_ data: Data, from socket: SAMSocket) {
        lock.lock()
        guard streamSocket === socket else { lock.unlock(); return }
        lastRead = Date()
        lock.unlock()

        feedBytes(data) { frame in
            counters.addRx(bytes: frame.count)
            if let raw = rawInboundHandler {
                raw(frame, self)
            } else if let packet = try? Packet.unpack(frame) {
                inboundHandler?(packet, self)
            }
        }
    }

    private func handleStreamClosed(_ socket: SAMSocket) {
        disconnect(ifCurrent: socket, reason: "Socket for \(displayName) was closed")
    }

    /// Take the peer offline and (unless detached) schedule a redial.
    /// Idempotent per connection: a stale socket's close events are ignored.
    private func disconnect(ifCurrent socket: SAMSocket?, reason: String) {
        lock.lock()
        if let socket, streamSocket !== socket { lock.unlock(); return }
        guard isOnline else { lock.unlock(); return }
        isOnline = false
        tunnelState = .initializing
        let sockets = [controlSocket, streamSocket].compactMap { $0 }
        controlSocket = nil
        streamSocket = nil
        let redial = !detached
        lock.unlock()

        stopWatchdog()
        sockets.forEach { $0.close() }
        Reticulum.log("\(reason), attempting to reconnect...", level: .warning)
        onDisconnected?(self)
        if redial { scheduleDial(after: retryInterval) }
    }

    // MARK: - Watchdog (Python: read_watchdog)

    private func startWatchdog() {
        stopWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + watchdogTick, repeating: watchdogTick)
        timer.setEventHandler { [weak self] in self?.watchdogTickFired() }
        lock.lock(); watchdog = timer; lock.unlock()
        timer.resume()
    }

    private func stopWatchdog() {
        lock.lock()
        let timer = watchdog
        watchdog = nil
        lock.unlock()
        timer?.cancel()
    }

    private func watchdogTickFired() {
        lock.lock()
        guard isOnline, let stream = streamSocket else { lock.unlock(); return }
        let sinceRead  = Date().timeIntervalSince(lastRead)
        let sinceWrite = Date().timeIntervalSince(lastWrite)

        // Python: tunnel goes stale after 2× probe-after without reads.
        if sinceRead > probeAfterInterval * 2 {
            if tunnelState != .stale {
                Reticulum.log("I2P tunnel became unresponsive", level: .debug)
            }
            tunnelState = .stale
        } else {
            tunnelState = .active
        }
        lock.unlock()

        // Python sends FLAG FLAG every tick once idle past probe-after
        // (last_write is only advanced by real traffic).
        if sinceWrite > probeAfterInterval {
            stream.write(Data([HDLC.flag, HDLC.flag]))
        }

        if sinceRead > readTimeoutInterval {
            disconnect(ifCurrent: stream,
                       reason: "I2P socket for \(displayName) is unresponsive, restarting")
        }
    }

    // MARK: - HDLC framing (outbound)

    /// HDLC-frame `data` exactly as BackboneInterface / TCPClientInterface do.
    /// Python: `data = bytes([HDLC.FLAG]) + HDLC.escape(data) + bytes([HDLC.FLAG])`
    public func hdlcFrame(_ data: Data) -> Data {
        var out = Data()
        out.append(HDLC.flag)
        for byte in data {
            switch byte {
            case HDLC.flag:
                out.append(HDLC.esc)
                out.append(HDLC.flag ^ HDLC.escMask)
            case HDLC.esc:
                out.append(HDLC.esc)
                out.append(HDLC.esc ^ HDLC.escMask)
            default:
                out.append(byte)
            }
        }
        out.append(HDLC.flag)
        return out
    }

    // MARK: - HDLC decoder (inbound)

    /// Feed raw bytes from the I2P socket into the HDLC state machine.
    /// Each complete frame is passed to `onFrame`. Empty frames (bare
    /// FLAG FLAG keepalives) are dropped.
    /// Python: the read_loop in `I2PInterfacePeer` does this inline.
    public func feedBytes(_ data: Data, onFrame: (Data) -> Void) {
        let mtu = hwMtu ?? Int.max
        for byte in data {
            if inFrame && byte == HDLC.flag {
                if !rxBuffer.isEmpty {
                    onFrame(rxBuffer)
                }
                rxBuffer.removeAll()
                inFrame = false
                escape  = false
            } else if byte == HDLC.flag {
                inFrame = true
                rxBuffer.removeAll()
                escape  = false
            } else if inFrame && rxBuffer.count < mtu {
                if byte == HDLC.esc {
                    escape = true
                } else if escape {
                    escape = false
                    if byte == (HDLC.flag ^ HDLC.escMask) {
                        rxBuffer.append(HDLC.flag)
                    } else if byte == (HDLC.esc ^ HDLC.escMask) {
                        rxBuffer.append(HDLC.esc)
                    } else {
                        rxBuffer.append(byte)
                    }
                } else {
                    rxBuffer.append(byte)
                }
            }
        }
    }
}

// (HDLC constants are defined in HDLC.swift and shared throughout the module)
