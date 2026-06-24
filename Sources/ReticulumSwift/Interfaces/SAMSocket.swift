import Foundation
import Network

// MARK: - SAMSocket errors

public enum SAMSocketError: Error, Equatable {
    case connectFailed(String)
    case timeout
    case closed
    /// A SAM command was answered with RESULT != OK.
    case samFailure(String)
}

// MARK: - SAMSocket protocol

/// One TCP connection to the SAM bridge of a running i2pd daemon.
///
/// SAM connections have two phases:
///  1. **Handshake** — line-oriented request/reply (`HELLO`, `SESSION CREATE`,
///     `NAMING LOOKUP`, `STREAM CONNECT`), driven by `write` + `readLine`.
///  2. **Data** — after `STREAM CONNECT` succeeds the same TCP connection
///     becomes the raw byte pipe to the remote I2P destination; entered with
///     `startStreaming`.
///
/// Follows the `RNodeTransport` pattern: `I2PInterfacePeer` speaks this
/// protocol, production uses `NWSAMSocket`, tests inject scripted sockets.
public protocol SAMSocket: AnyObject {
    /// Open the TCP connection to the SAM bridge. Blocks the calling thread
    /// until connected or throws. Never call from the socket's own queue.
    func connect(timeout: TimeInterval) throws

    /// Send raw bytes (SAM command lines during handshake, stream data after).
    func write(_ data: Data)

    /// Read one LF-terminated reply line (without the newline). Blocks the
    /// calling thread up to `timeout`.
    func readLine(timeout: TimeInterval) throws -> String

    /// Switch to the data phase: every received byte from now on — including
    /// any bytes that arrived after the last reply line — is passed to
    /// `handler`. `onClose` fires once when the connection dies remotely or
    /// errors (not on local `close()`).
    func startStreaming(_ handler: @escaping (Data) -> Void,
                        onClose: @escaping () -> Void)

    /// Close the connection. Suppresses `onClose`.
    func close()
}

// MARK: - NWSAMSocket (production implementation)

/// `SAMSocket` over `NWConnection`, always to the local SAM bridge
/// (`127.0.0.1:<samPort>`). The blocking handshake calls are intended to run
/// on a peer's dedicated dial queue — mirroring Python's thread-per-peer
/// `tunnel_job` model — while NWConnection callbacks run on an internal queue.
public final class NWSAMSocket: SAMSocket {

    private let host: String
    private let port: UInt16
    private let queue: DispatchQueue
    private var conn: NWConnection?

    private let cond = NSCondition()
    // All state below is guarded by `cond`.
    private var buffer = Data()
    private var ready = false
    private var failed = false
    private var closed = false
    private var locallyClosed = false
    private var streamHandler: ((Data) -> Void)?
    private var closeHandler: (() -> Void)?

    public init(host: String = "127.0.0.1", port: UInt16) {
        self.host = host
        self.port = port
        self.queue = DispatchQueue(label: "ReticulumSwift.NWSAMSocket.\(port)")
    }

    public func connect(timeout: TimeInterval) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw SAMSocketError.connectFailed("invalid SAM port \(port)")
        }
        let connection = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(host), port: nwPort),
            using: .tcp
        )
        conn = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.cond.lock(); self.ready = true; self.cond.broadcast(); self.cond.unlock()
                self.receiveLoop(connection)
            case .failed, .cancelled:
                self.markClosed()
            default:
                break
            }
        }
        connection.start(queue: queue)

        let deadline = Date().addingTimeInterval(timeout)
        cond.lock()
        while !ready && !failed && !closed {
            if !cond.wait(until: deadline) { break }
        }
        let ok = ready
        cond.unlock()
        guard ok else {
            connection.cancel()
            throw SAMSocketError.connectFailed("SAM bridge at \(host):\(port) unreachable")
        }
    }

    public func write(_ data: Data) {
        conn?.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.markClosed() }
        })
    }

    public func readLine(timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        cond.lock()
        defer { cond.unlock() }
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex ..< nl]
                buffer.removeSubrange(buffer.startIndex ... nl)
                return String(decoding: lineData, as: UTF8.self)
                    .trimmingCharacters(in: .init(charactersIn: "\r"))
            }
            if closed { throw SAMSocketError.closed }
            if !cond.wait(until: deadline) { throw SAMSocketError.timeout }
        }
    }

    public func startStreaming(_ handler: @escaping (Data) -> Void,
                               onClose: @escaping () -> Void) {
        cond.lock()
        streamHandler = handler
        closeHandler = onClose
        // Bytes pipelined by the remote right behind the STREAM STATUS line
        // must not be lost — drain them into the data phase first.
        let leftover = buffer
        buffer.removeAll()
        let alreadyClosed = closed && !locallyClosed
        cond.unlock()

        if !leftover.isEmpty { handler(leftover) }
        if alreadyClosed { onClose() }
    }

    public func close() {
        cond.lock()
        locallyClosed = true
        closed = true
        cond.broadcast()
        cond.unlock()
        conn?.cancel()
        conn = nil
    }

    // MARK: - Internals

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.cond.lock()
                let handler = self.streamHandler
                if handler == nil { self.buffer.append(data) }
                self.cond.broadcast()
                self.cond.unlock()
                handler?(data)
            }
            if error != nil || isComplete {
                self.markClosed()
                return
            }
            self.receiveLoop(connection)
        }
    }

    /// Mark the connection dead and fire `closeHandler` exactly once
    /// (unless the close was locally requested).
    private func markClosed() {
        cond.lock()
        let wasClosed = closed
        let local = locallyClosed
        closed = true
        if !ready { failed = true }
        let handler = closeHandler
        closeHandler = nil
        cond.broadcast()
        cond.unlock()
        if !wasClosed && !local { handler?() }
    }
}
